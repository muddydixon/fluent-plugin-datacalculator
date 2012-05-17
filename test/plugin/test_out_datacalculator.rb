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

  def create_driver(conf = CONFIG, tag='test.input')
    Fluent::Test::OutputTestDriver.new(Fluent::DataCalculatorOutput, tag).configure(conf)
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
    assert_equal false, d.instance.outcast_unmatched

  end

  def test_count_initialized
    d = create_driver %[
      aggregate all
      formulas sum = amount * price, cnt = amount
    ]
    assert_equal [0,0,0], d.instance.counts['all']
  end

  def test_create_formula
    d = create_driver %[
      aggregate all
      formulas sum = amount * price, cnt = amount
    ]
    assert_equal 0, d.instance._formulas[0][0]
    assert_equal 'unmatched', d.instance._formulas[0][1]
    assert_equal nil, d.instance._formulas[0][2]
    assert_equal 1, d.instance._formulas[1][0]
    assert_equal 'sum', d.instance._formulas[1][1]
    assert_equal ['amount', 'price'], d.instance._formulas[1][2]
    assert_equal 2, d.instance._formulas[2][0]
    assert_equal 'cnt', d.instance._formulas[2][1]
    assert_equal ['amount'], d.instance._formulas[2][2]
  end

  def test_countups
    d = create_driver
    assert_nil d.instance.counts['test.input']
    d.instance.countups('test.input', [0, 0, 0, 0])
    assert_equal [0,0,0,0], d.instance.counts['test.input']
    d.instance.countups('test.input', [1, 1, 1, 0])
    assert_equal [1,1,1,0], d.instance.counts['test.input']
    d.instance.countups('test.input', [0, 5, 1, 0])
    assert_equal [1,6,2,0], d.instance.counts['test.input']
  end

  def test_stripped_tag
    d = create_driver
    assert_equal 'input', d.instance.stripped_tag('test.input')
    assert_equal 'test.input', d.instance.stripped_tag('test.test.input')
    assert_equal 'input', d.instance.stripped_tag('input')
  end

  def test_generate_output
    d = create_driver
    r1 = d.instance.generate_output({'test.input' => [60,240,120,180], 'test.input2' => [0,600,0,0]}, 60)

    assert_equal   60, r1['input_unmatched']
    assert_equal   240, r1['input_sum']
    assert_equal   120, r1['input_amounts']
    assert_equal   180, r1['input_record']
    assert_equal   2, r1['input_ave']

    assert_equal   0, r1['input2_unmatched']
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

    r2 = d.instance.generate_output({'all' => [60,240,120,180]}, 60)
    assert_equal   60, r2['unmatched']
    assert_equal   240, r2['sum']
    assert_equal   120, r2['amounts']
    assert_equal   180, r2['record']
    assert_equal   2, r2['ave']
  end

  def test_emit
    d1 = create_driver(CONFIG, 'test.input')
    d1.run do
      60.times do
        d1.emit({'amount' => 3, 'price' => 100})
        d1.emit({'amount' => 3, 'price' => 200})
        d1.emit({'amount' => 6, 'price' => 50})
        d1.emit({'amount' => 10, 'price' => 100})
      end
    end
    r1 = d1.instance.flush(60)
    assert_equal 0, r1['input_unmatched']
    assert_equal 132000, r1['input_sum']
    assert_equal 1320, r1['input_amounts']
    assert_equal 240, r1['input_record']
    assert_equal 100.0, r1['input_ave']

    d2 = create_driver(%[
      unit minute
      aggregate all
      input_tag_remove_prefix test
      formulas sum = amount * price, amounts = amount, record = 1
      finalizer ave = amounts > 0 ? 1.0 * sum / amounts : 0
    ], 'test.input2')

    d2.run do
      60.times do
        d2.emit({'amount' => 3, 'price' => 100})
        d2.emit({'amount' => 3, 'price' => 200})
        d2.emit({'amount' => 6, 'price' => 50})
        d2.emit({'amount' => 10, 'price' => 100})
      end
    end
    r2 = d2.instance.flush(60)
    assert_equal 0, r2['unmatched']
    assert_equal 132000, r2['sum']
    assert_equal 1320, r2['amounts']
    assert_equal 240, r2['record']
    assert_equal 100.0, r2['ave']
  end
end
