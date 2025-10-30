# ractor-shim

A shim to define `Ractor` by using `Thread`, `Queue`, etc if `Ractor` is not already defined.

This is notably useful to run programs relying on `Ractor` on Ruby implementations which don't define `Ractor` such as TruffleRuby and JRuby.

Note that TruffleRuby and JRuby both run Ruby code in threads in parallel, so this gem enables using the Ractor API on these Rubies and run Ractors in parallel.

The gem also provides the Ruby 3.5 Ractor API  (`Ractor::Port`, `Ractor#{join,value,monitor}`, etc) for CRuby 2.7 to 3.4.

When `Ractor` is not already defined, this gem implements `Ractor.make_shareable(object)` by just returning `object` to avoid unnecessary overhead. The reason is that the CRuby implementation of `Ractor.make_shareable` returns an immutable object, so it won't be mutated by the program anyway and there is no need to deep freeze.

## Installation

```bash
$ gem install ractor-shim
```
or
```ruby
# In Gemfile
gem "ractor-shim"
```

## Usage

```ruby
require 'ractor/shim'

Ractor.new { ... }
```

## Development

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `ractor-shim.gemspec`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/eregon/ractor-shim.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
