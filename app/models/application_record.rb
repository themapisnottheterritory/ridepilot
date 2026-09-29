class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  # a save refused with a reason the person sees -> trouble board (TroubleWatch)
  after_validation { TroubleWatch.validation_failed(self) }
end