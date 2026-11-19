require "simplecov-cobertura"

SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::CoberturaFormatter
]

SimpleCov.use_merging true
SimpleCov.merge_timeout 3600

SimpleCov.add_filter "/test/"
