# -*- coding: utf-8 -*-
require 'helper'

class DataCalculatorOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
    unit minute
    aggregate tag
    input_tag_remove_prefix test
    formulas sum = amount * price, amounts = amount, record = 1
    finalizer ave = amounts > 0 ? 1.0 * sum / amounts : 0
  ]

  def create_driver(conf = CONFIG)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::DataCalculatorOutput).configure(conf)
  end

  def test_configure
    assert_raise(Fluent::ConfigError) {
      d = create_driver('')
    }
    # 式がSyntax Error
    assert_raise(Fluent::ConfigError) {
      d = create_driver %[
        formulas sum = 10 ab
      ]
    }
    # aggregateに必要な要素がない
    assert_raise(Fluent::ConfigError) {
      d = create_driver %[
        aggregate keys
      ]
    }
    # finalizerに必要な要素がない
    assert_raise(Fluent::ConfigError) {
      d = create_driver %[
        finalizer ave = cnt > 0 ? sum / cnt : 0
      ]
    }
    # finalizerに必要な要素がない
    assert_raise(Fluent::ConfigError) {
      d = create_driver %[
        formulas sum = 10
        finalizer ave = cnt > 0 ? sum / cnt : 0
      ]
    }
    d = create_driver %[
      formulas sum = amount * price, cnt = amount
      finalizer ave = cnt > 0 ? sum / cnt : 0
    ]
    assert_equal 60, d.instance.tick
    assert_equal :tag, d.instance.aggregate
    assert_equal 'datacalculate', d.instance.tag
    assert_nil d.instance.input_tag_remove_prefix
    assert_equal 'sum = amount * price, cnt = amount', d.instance.formulas
    assert_equal 'ave = cnt > 0 ? sum / cnt : 0', d.instance.finalizer

  end

  def test_count_initialized
    d = create_driver %[
      aggregate all
      formulas sum = amount * price, cnt = amount
    ]
    assert_equal [0,0], d.instance.counts['all']
  end

  def test_create_formula
    d = create_driver %[
      aggregate all
      formulas sum = amount * price, cnt = amount
    ]
    assert_equal 0, d.instance._formulas[0][0]
    assert_equal 'sum', d.instance._formulas[0][1]
    assert_equal ['amount', 'price'], d.instance._formulas[0][2]
    assert_equal 1, d.instance._formulas[1][0]
    assert_equal 'cnt', d.instance._formulas[1][1]
    assert_equal ['amount'], d.instance._formulas[1][2]
  end

  def test_countups
    d = create_driver
    assert_nil d.instance.counts['test.input']
    d.instance.countups('test.input', [0, 0, 0])
    assert_equal [0,0,0], d.instance.counts['test.input']
    d.instance.countups('test.input', [1, 1, 0])
    assert_equal [1,1,0], d.instance.counts['test.input']
    d.instance.countups('test.input', [5, 1, 0])
    assert_equal [6,2,0], d.instance.counts['test.input']
  end

  def test_stripped_tag
    d = create_driver
    assert_equal 'input', d.instance.stripped_tag('test.input')
    assert_equal 'test.input', d.instance.stripped_tag('test.test.input')
    assert_equal 'input', d.instance.stripped_tag('input')
  end

  def test_aggregate_keys
    d = create_driver %[
      aggregate keys area_id, mission_id
      formulas sum = amount * price, cnt = amount
    ]
    assert_equal 'keys', d.instance.aggregate
    assert_equal ['area_id', 'mission_id'], d.instance.aggregate_keys
  end

  def test_generate_output
    d = create_driver
    r1 = d.instance.generate_output({'test.input' => [240,120,180], 'test.input2' => [600,0,0]}, 60)[0]


    assert_equal   240, r1['input_sum']
    assert_equal   120, r1['input_amounts']
    assert_equal   180, r1['input_record']
    assert_equal   2, r1['input_ave']

    assert_equal   600, r1['input2_sum']
    assert_equal   0, r1['input2_amounts']
    assert_equal   0, r1['input2_record']
    assert_equal   0, r1['input2_ave']

    d = create_driver %[
      aggregate all
      input_tag_remove_prefix test
      formulas sum = amount * price, amounts = amount, record = 1
      finalizer ave = amounts > 0 ? sum / amounts : 0
    ]

    r2 = d.instance.generate_output({'all' => [240,120,180]}, 60)[0]
    assert_equal   240, r2['sum']
    assert_equal   120, r2['amounts']
    assert_equal   180, r2['record']
    assert_equal   2, r2['ave']

  end

  def test_emit
    d1 = create_driver(CONFIG)
    d1.run(default_tag: 'test.input1') do
      60.times do
        d1.feed({'amount' => 3, 'price' => 100})
        d1.feed({'amount' => 3, 'price' => 200})
        d1.feed({'amount' => 6, 'price' => 50})
        d1.feed({'amount' => 10, 'price' => 100})
      end
      r1 = d1.instance.flush(60)[0]
      assert_equal 132000, r1['input1_sum']
      assert_equal 1320, r1['input1_amounts']
      assert_equal 240, r1['input1_record']
      assert_equal 100.0, r1['input1_ave']
    end

    d2 = create_driver(%[
      unit minute
      aggregate all
      input_tag_remove_prefix test
      formulas sum = amount * price, amounts = amount, record = 1
      finalizer ave = amounts > 0 ? 1.0 * sum / amounts : 0
    ])

    d2.run(default_tag: 'test.input2') do
      60.times do
        d2.feed({'amount' => 3, 'price' => 100})
        d2.feed({'amount' => 3, 'price' => 200})
        d2.feed({'amount' => 6, 'price' => 50})
        d2.feed({'amount' => 10, 'price' => 100})
      end
    end
    r2 = d2.instance.flush(60)[0]
    assert_equal 132000, r2['sum']
    assert_equal 1320, r2['amounts']
    assert_equal 240, r2['record']
    assert_equal 100.0, r2['ave']

    d3 = create_driver(%[
      unit minute
      aggregate keys area_id, mission_id
      formulas sum = amount * price, count = 1
      <unmatched>
        type stdout
      </unmatched>
    ])

    sums = {}
    counts = {}
    d3.run(default_tag: 'test.input3') do
      240.times do
        area_id = rand(5)
        mission_id = rand(5)
        amount = rand(10)
        price = rand(5) * 100
        pat = [area_id, mission_id].join(',')
        d3.feed({'amount' => amount, 'price' => price, 'area_id' => area_id, 'mission_id' => mission_id})
        sums[pat] = 0 unless sums.has_key?(pat)
        counts[pat] = 0 unless counts.has_key?(pat)
        sums[pat] += amount * price
        counts[pat] += 1
      end
    end
    r3 = d3.instance.flush(60)
    r3.each do |r|
      pat = [r['area_id'], r['mission_id']].join(',')
      assert_equal sums[pat], r['sum']
      assert_equal counts[pat], r['count']
    end

    d4 = create_driver(%[
      unit minute
      aggregate keys area_id, mission_id
      formulas sum = amount * price, count = 1
      <unmatched>
        type stdout
      </unmatched>
    ])

    sums = {}
    counts = {}
    d4.run(default_tag: 'test.input3') do
      240.times do
        area_id = 'area_'+rand(5).to_s
        mission_id = 'mission_'+rand(5).to_s
        amount = rand(10)
        price = rand(5) * 100
        pat = [area_id, mission_id].join('_$_')
        d4.feed({'amount' => amount, 'price' => price, 'area_id' => area_id, 'mission_id' => mission_id})
        sums[pat] = 0 unless sums.has_key?(pat)
        counts[pat] = 0 unless counts.has_key?(pat)
        sums[pat] += amount * price
        counts[pat] += 1
      end
    end
    r4 = d4.instance.flush(60)
    r4.each do |r|
      pat = [r['area_id'], r['mission_id']].join('_$_')
      assert_equal sums[pat], r['sum']
      assert_equal counts[pat], r['count']
    end
  end

  def test_flush
    # retain_key_combinations is true
    d1 = create_driver(%[
      unit minute
      aggregate keys area_id, mission_id
      formulas sum = amount * price, count = 1
      retain_key_combinations true
    ])
    d1.run(default_tag: 'test.input') do
      60.times do
        d1.feed({'area_id' => 1, 'mission_id' => 1, 'amount' => 3, 'price' => 100})
        d1.feed({'area_id' => 2, 'mission_id' => 1, 'amount' => 3, 'price' => 100})
      end
    end
    assert_equal d1.instance.flush(60).size, 2
    assert_equal d1.instance.flush(60).size, 2

    # retain_key_combinations is false
    d2 = create_driver(%[
      unit minute
      aggregate keys area_id, mission_id
      formulas sum = amount * price, count = 1
      retain_key_combinations false
    ])
    d2.run(default_tag: 'test.input') do
      60.times do
        d2.feed({'area_id' => 1, 'mission_id' => 1, 'amount' => 3, 'price' => 100})
        d2.feed({'area_id' => 2, 'mission_id' => 1, 'amount' => 3, 'price' => 100})
      end
    end
    assert_equal d2.instance.flush(60).size, 2
    assert_equal d2.instance.flush(60).size, 0
  end
end
