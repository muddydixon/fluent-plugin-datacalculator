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

  def test_create_formula

    # case: common case
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

    assert_equal 200, d.instance._formulas[0][3].call(10, 20)
    assert_equal 20, d.instance._formulas[1][3].call(20)
    assert_raise(ArgumentError){
      d.instance._formulas[0][3].call(10)
    }

    # case: use Class
    d = create_driver %[
      aggregate all
      formulas time = Fluent::Engine.now
    ]
    assert_equal 0, d.instance._formulas[0][0]
    assert_equal 'time', d.instance._formulas[0][1]
    assert_equal [], d.instance._formulas[0][2]
    assert_equal Time.now.to_i, d.instance._formulas[0][3].call()

    # case: use instance.method
    d = create_driver %[
      aggregate all
      formulas sum = amount.to_i * price, cnt = amount
    ]
    assert_equal 0, d.instance._formulas[0][0]
    assert_equal 'sum', d.instance._formulas[0][1]
    assert_equal ['amount', 'price'], d.instance._formulas[0][2]
    assert_equal 1, d.instance._formulas[1][0]
    assert_equal 'cnt', d.instance._formulas[1][1]
    assert_equal ['amount'], d.instance._formulas[1][2]

    assert_equal 200, d.instance._formulas[0][3].call("10", 20)
    assert_equal 20, d.instance._formulas[1][3].call(20)
    assert_raise(ArgumentError){
      d.instance._formulas[0][3].call(10)
    }

    # case: use string
    d = create_driver %[
      aggregate all
      formulas cnt = 1
      finalizer name = "muddy" + "dixon" + cnt.to_s
    ]
    assert_equal 0, d.instance._finalizer[0]
    assert_equal ['cnt'], d.instance._finalizer[2]
    assert_equal "muddydixon20", d.instance._finalizer[3].call(20)
  end
end
