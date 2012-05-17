class Fluent::DataCalculatorOutput < Fluent::Output
  Fluent::Plugin.register_output('datacalculate', self)

  config_param :count_interval, :time, :default => nil
  config_param :unit, :string, :default => 'minute'
  config_param :aggregate, :string, :default => 'tag'
  config_param :tag, :string, :default => 'datacalculate'
  config_param :input_tag_remove_prefix, :string, :default => nil
  config_param :formulas, :string
  config_param :finalizer, :string, :default => nil
  config_param :outcast_unmatched, :bool, :default => false

  attr_accessor :tick
  attr_accessor :counts
  attr_accessor :last_checked
  attr_accessor :_formulas
  attr_accessor :_finalizer

  def configure(conf)
    super

    if @count_interval
      @tick = @count_interval.to_i
    else
      @tick = case @unit
              when 'minute' then 60
              when 'hour' then 3600
              when 'day' then 86400
              else 
                raise RuntimeError, "@unit must be one of minute/hour/day"
              end
    end

    @aggregate = case @aggregate
                 when 'tag' then :tag
                 when 'all' then :all
                 else
                   raise Fluent::ConfigError, "flowcounter aggregate allows tag/all"
                 end

    def createFunc (cnt, str)
      str.strip!
      left, right = str.split(/\s*=\s*/, 2)
      rights = right.scan(/[a-zA-Z][\w\d_\.\$]*/).uniq
      
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
        _argv.push obj[arg]
      }
      formula.call(*_argv)
    end

    @_formulas = [[0, 'unmatched', nil, nil]]
    if conf.has_key?('formulas')
      fs = conf['formulas'].split(/\s*,\s*/)
      fs.each_with_index { |str,i |
        @_formulas.push( createFunc(i + 1, str) )
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
    start_watch
  end

  def shutdown
    super
    @watcher.terminate
    @watcher.join
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
    output = {}
    if @aggregate == :all
      # index 0 is unmatched
      sum = if @outcast_unmatched
              counts['all'][1..-1].inject(:+)
            else
              counts['all'].inject(:+)
            end
      counts['all'].each_with_index do |count,i|
        name = @_formulas[i][1]
        output[name] = count
      end

      if @_finalizer
        output[@_finalizer[1]] = execFunc('all', output, @_finalizer[2], @_finalizer[3])
      end

      return output
    end

    counts.keys.each do |tag|
      t = stripped_tag(tag)
      sum = if @outcast_unmatched
              counts[tag][1..-1].inject(:+)
            else
              counts[tag].inject(:+)
            end
      counts[tag].each_with_index do |count,i|
        name = @_formulas[i][1]
        output[t + '_' + name] = count
      end
      if @_finalizer
        output[t + '_' + @_finalizer[1]] = execFunc(tag, output, @_finalizer[2], @_finalizer[3])
      end
    end
    output
  end

  def flush(step)
    flushed,@counts = @counts,count_initialized(@counts.keys.dup)
    generate_output(flushed, step)
  end

  def flush_emit(step)
    Fluent::Engine.emit(@tag, Fluent::Engine.now, flush(step))
  end

  def start_watch
    # for internal, or tests only
    @watcher = Thread.new(&method(:watch))
  end
  
  def watch
    # instance variable, and public accessable, for test
    @last_checked = Fluent::Engine.now
    while true
      sleep 0.5
      if Fluent::Engine.now - @last_checked >= @tick
        now = Fluent::Engine.now
        flush_emit(now - @last_checked)
        @last_checked = now
      end
    end
  end

  def checkArgs (obj, inkeys)
    inkeys.each{ |key|
      if not obj.has_key?(key)
        return false
      end
    }
    return true
  end

  def emit(tag, es, chain)
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

    chain.next
  end
end
