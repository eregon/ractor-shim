# ractor-shim

A shim to define `Ractor` by using `Thread`, if `Ractor` is not already defined.

This is notably useful to run programs needing `Ractor` on Ruby implementations which don't define `Ractor.

## Usage

```ruby
require 'ractor/shim'
```

## Development

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `ractor-shim.gemspec`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/eregon/ractor-shim.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
