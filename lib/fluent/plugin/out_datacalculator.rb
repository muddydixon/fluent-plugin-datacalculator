# -*- coding: utf-8 -*-
require 'fluent/plugin/output'

class Fluent::DataCalculatorOutput < Fluent::Output
  Fluent::Plugin.register_output('datacalculator', self)
  
  helpers :event_emitter, :timer

  config_param :count_interval, :time, :default => nil
  config_param :unit, :string, :default => 'minute'
  config_param :aggregate, :string, :default => 'tag'
  config_param :aggregate_delimiter, :string, :default => '_$_'
  config_param :tag, :string, :default => 'datacalculate'
  config_param :input_tag_remove_prefix, :string, :default => nil
  config_param :formulas, :string
  config_param :finalizer, :string, :default => nil
  config_param :retain_key_combinations, :bool, :default => true

  attr_accessor :tick
  attr_accessor :counts
  attr_accessor :last_checked
  attr_accessor :aggregate_keys
  attr_accessor :_formulas
  attr_accessor :_finalizer

  def configure(conf)
    super

    if @count_interval
      @tick = @count_interval.to_i
    else
      if @unit.index('sec') == 0
        @tick = 1
      elsif @unit.index('sec') != nil
        @tick = @unit[0, @unit.index('sec')].to_i
      elsif @unit.index('minute') == 0
        @tick = 60
      elsif @unit.index('minute') != nil
        @tick = @unit[0, @unit.index('minute')].to_i * 60
      elsif @unit.index('hour') == 0
        @tick = 3600
      elsif @unit.index('hour') != nil
        @tick = @unit[0, @unit.index('hour')].to_i * 3600
      elsif @unit.index('day') == 0
        @tick = 86400
      elsif @unit.index('day') != nil
        @tick = @unit[0, @unit.index('day')].to_i * 86400
      else
        raise RuntimeError, "@unit must be one of Xsec[onds]/Xminute[s]/Xhour[s]/Xday[s]"
      end
    end


    conf.elements.each do |element|
      element.keys.each do |k|
        element[k]
      end

      case element.name
      when 'unmatched'
        @unmatched = element
      end
    end
    # TODO: unmatchedの時に別のタグを付けて、ふってあげないと行けない気がする
    # unmatchedの定義
    # 1. aggregate_keys を持たないレコードが入ってきた時
    # 2. fomulaで必要な要素がなかったレコードが入ってきた時
    # 3. fomulaで集計可能な数値でない場合(文字列や真偽値、正規表現、ハッシュ、配列など)

    @aggregate_keys = []
    @aggregate = case @aggregate
                 when 'tag' then :tag
                 when 'all' then :all
                 else
                   if @aggregate.index('keys') == 0
                     @aggregate_keys = @aggregate.split(/\s/, 2)[1]
                     unless @aggregate_keys
                       raise Fluent::ConfigError, "aggregate_keys require in keys"
                     end
                     @aggregate_keys = @aggregate_keys.split(/\s*,\s*/)
                     @aggregate = 'keys'
                   else
                     raise Fluent::ConfigError, "flowcounter aggregate allows tag/all"
                   end
                 end

    def createFunc (cnt, str)
      str.strip!
      left, right = str.split(/\s*=\s*/, 2)
      # Fluent moduleだけはOK
      rights = right.scan(/[a-zA-Z][\w\d_\.\$\:\@]*/).uniq.select{|x| x.index('Fluent') != 0}

      begin
        f = eval('lambda {|'+rights.join(',')+'|  '+right + '}')
      rescue SyntaxError
        raise Fluent::ConfigError, "'" + str + "' is not valid"
      end

      [cnt, left, rights, f]
    end

    def execFunc (tag, obj, argv, formula)
      if tag != nil
        tag = stripped_tag (tag)
      end
      _argv = []

      argv.each {|arg|
        if tag != nil and tag != 'all'
          arg = tag + '_' + arg
        end
        _argv.push obj[arg].to_f
      }
      formula.call(*_argv)
    end

    @_formulas = []
    if conf.has_key?('formulas')
      fs = conf['formulas'].split(/\s*,\s*/)
      fs.each_with_index { |str,i |
        @_formulas.push( createFunc(i, str) )
      }
    end

    if conf.has_key?('finalizer')
      @_finalizer = createFunc(0, conf['finalizer'])

      # check finalizer field
      cnt = @_finalizer[2].length
      @_finalizer[2].each { |key|
        @_formulas.each { |formula|
          next if formula[2] == nil
          cnt -= 1 if formula[1] == key
        }
      }
      if cnt != 0
        raise Fluent::ConfigError, 'keys in finalizer is not satisfied'
      end
    end

    if @input_tag_remove_prefix
      @removed_prefix_string = @input_tag_remove_prefix + '.'
      @removed_length = @removed_prefix_string.length
    end

    @counts = count_initialized
    @mutex = Mutex.new
  end

  def start
    super
    @last_checked = 0
    timer_execute(:out_datacalculator_timer, @tick, &method(:watch))
  end

  def count_initialized(keys=nil)
    # counts['tag'][num] = count
    if @aggregate == :all
      {'all' => ([0] * @_formulas.length)}
    elsif keys
      values = Array.new(keys.length) {|i|
        Array.new(@_formulas.length){|j| 0 }
      }
      Hash[[keys, values].transpose]
    else
      {}
    end
  end

  def countups(tag, counts)
    if @aggregate == :all
      tag = 'all'
    end

    @mutex.synchronize {
      @counts[tag] ||= [0] * @_formulas.length
      counts.each_with_index do |count, i|
        @counts[tag][i] += count
      end
    }
  end

  def stripped_tag(tag)
    return tag unless @input_tag_remove_prefix
    return tag[@removed_length..-1] if tag.start_with?(@removed_prefix_string) and tag.length > @removed_length
    return tag[@removed_length..-1] if tag == @input_tag_remove_prefix
    tag
  end

  def generate_output(counts, step)
    if @aggregate == :all
      output = {}
      counts['all'].each_with_index do |count,i|
        name = @_formulas[i][1]
        output[name] = count
      end

      if @_finalizer
        output[@_finalizer[1]] = execFunc('all', output, @_finalizer[2], @_finalizer[3])
      end

      return [output]
    end

    if @aggregate == 'keys'
      outputs = []

      counts.keys.each do |pat|
        output = {}
        pat_val = pat.split(@aggregate_delimiter).map{|x| x.to_s }
        counts[pat].each_with_index do |count, i|
          name = @_formulas[i][1]
          output[name] = count
        end

        @aggregate_keys.each_with_index do |key, i|
          output[@aggregate_keys[i]] = pat_val[i]
        end

        if @_finalizer
          output[@_finalizer[1]] = execFunc('all', output, @_finalizer[2], @_finalizer[3])
        end

        outputs.push(output)
      end

      return outputs
    end

    output = {}
    counts.keys.each do |tag|
      t = stripped_tag(tag)
      counts[tag].each_with_index do |count,i|
        name = @_formulas[i][1]
        output[t + '_' + name] = count
      end
      if @_finalizer
        output[t + '_' + @_finalizer[1]] = execFunc(tag, output, @_finalizer[2], @_finalizer[3])
      end
    end
    [output]
  end

  def flush(step)
    if @retain_key_combinations
      flushed, @counts = @counts,count_initialized(@counts.keys.dup)
    else
      flushed, @counts = @counts,count_initialized
    end
    generate_output(flushed, step)
  end

  def flush_emit(step)
    data = flush(step)
    data.each do |dat|
      router.emit(@tag, Fluent::Engine.now, dat)
    end
  end

  def start_watch
    # for internal, or tests only
    @watcher = Thread.new(&method(:watch))
  end

  def watch
    now = Fluent::Engine.now
    flush_emit(now - @last_checked)
    @last_checked = now
  end

  def checkArgs (obj, inkeys)
    inkeys.each{ |key|
      if not obj.has_key?(key)
        return false
      end
    }
    return true
  end

  def process (tag, es)

    if @aggregate == 'keys'
      emit_aggregate_keys(tag, es)
    else
      emit_single_tag(tag, es)
    end
  end

  def emit_aggregate_keys (tag, es)
    cs = {}
    es.each do |time, record|
      matched = false
      pat = @aggregate_keys.map{ |key| record[key] }.join(@aggregate_delimiter)
      cs[pat] = [0] * @_formulas.length unless cs.has_key?(pat)

      if @_formulas.length > 0
        @_formulas.each do | index, outkey, inkeys, formula|
          next unless formula and checkArgs(record, inkeys)

          cs[pat][index] += execFunc('all', record, inkeys, formula)
          matched = true
        end
      else
        $log.warn index
      end
      cs[pat][0] += 1 unless matched
    end

    cs.keys.each do |pat|
      countups(pat, cs[pat])
    end
  end

  def emit_single_tag (tag, es)
    c = [0] * @_formulas.length

    es.each do |time,record|
      matched = false
      if @_formulas.length > 0
        @_formulas.each do |index, outkey, inkeys, formula|
          next unless formula and checkArgs(record, inkeys)
          c[index] += execFunc(nil, record, inkeys, formula)
          matched = true
        end
      else
        $log.warn index
      end
      c[0] += 1 unless matched
    end

    countups(tag, c)
  end
end
