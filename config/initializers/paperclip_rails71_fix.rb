# Paperclip 6.1.0 references NumericalityValidator::CHECKS which was renamed
# to COMPARE_CHECKS in Rails 7.1. This patch restores the constant.
if defined?(ActiveModel::Validations::NumericalityValidator)
  unless ActiveModel::Validations::NumericalityValidator.const_defined?(:CHECKS)
    ActiveModel::Validations::NumericalityValidator.const_set(
      :CHECKS,
      ActiveModel::Validations::NumericalityValidator::COMPARE_CHECKS
    )
  end
end
