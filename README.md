# Fluent::Plugin::Datacalculator, a plugin for [Fluentd](http://fluentd.org/)  [![Build Status](https://travis-ci.org/muddydixon/fluent-plugin-datacalculator.png?branch=master)](https://travis-ci.org/muddydixon/fluent-plugin-datacalculator)



Simple Calculate messages and summarize the calculated results.

* Summarize calculated results per min/hour/day
* Summarize calculated results per second (average every min/hour/day)
* Use finalizer of summarized results (e.g. average)

## Usage

if fluentd set like that:

```
<match payment.shop>
  type datacalculator
  tag result.shop
  count_interval 5s
  aggregate all
  formulas sum = amount * price, cnt = 1, total = amount
  finalizer ave = cnt > 0 ? 1.00 * sum / cnt : 0
</match>
```

recieves bellow messages in a minute:

```
{"area_id": 1, "mission_id":1, "amount": 3, "price": 100}
{"area_id": 2, "mission_id":2, "amount": 2, "price": 200}
{"area_id": 3, "mission_id":1, "amount": 3, "price": 100}
{"area_id": 4, "mission_id":1, "amount": 4, "price": 300}
{"area_id": 5, "mission_id":2, "amount": 5, "price": 200}
{"area_id": 1, "mission_id":1, "amount": 1, "price": 400}
{"area_id": 4, "mission_id":1, "amount": 2, "price": 200}
{"area_id": 3, "mission_id":2, "amount": 1, "price": 300}
```

then output below:

```
2014-02-26 13:52:28 +0900 result.shop: {"sum":4300.0,"cnt":8,"total":21.0,"ave":537.5}
```

## Configuration

### Example

```
<match accesslog.**>
  type datacalculate
  unit minute
  aggregate all
  fomulas sum = amount * price, amounts = amount
</match>
```

If you use finalizer, like this

```
<match accesslog.**>
  type datacalculate
  unit minute
  aggregate all
  fomulas sum = amount * price, amounts = amount
  finalizer average = amounts > 0 ? 1.0 * sum / amounts : 0
</match>
```

Finalizer uses the summarized output, so argv in finalizer must exist in left-hand side in fomulas.

### Options

* `count_interval`: aggregate time interval e.g. `5s`, `15m`, `3h`
* `aggregate`: if set `all` then all matched tags are aggregated. if set `tag` then each tags are aggregated separately (default `tag`).
* `input_tag_remove_prefix`: option available if you want to remove tag prefix from output field names. This option available when aggregate is set `tag`.
* `retain_key_combinations`: option available if you want to retain key combination created in previous to next interval (default `true`).
* `formulas`: define value and function comma separated. values are set in messages.
* `finalizer`: functions defined are executed aggregated phase. value are set in messages.

## TODO

* multiple finalizer

## Copyright

Copyright:: Copyright (c) 2012- Muddy Dixon
License::   Apache License, Version 2.0
