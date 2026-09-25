# Paperclip 6.1 calls errors.add(attribute, type, options_hash) with the options
# as a third positional argument. Rails 7.1's ActiveModel::Errors#add takes
# keyword options only, so every failed attachment validation (missing file,
# wrong content type, too big) raised ArgumentError and returned a 500 instead
# of a validation message. Fold a trailing positional Hash into the keywords.
module ErrorsAddPositionalOptions
  def add(attribute, type = :invalid, *rest, **options)
    options = rest.first.merge(options) if rest.size == 1 && rest.first.is_a?(Hash)
    super(attribute, type, **options)
  end
end
ActiveModel::Errors.prepend(ErrorsAddPositionalOptions)
