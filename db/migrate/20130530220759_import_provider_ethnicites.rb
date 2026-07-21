class ImportProviderEthnicites < ActiveRecord::Migration[4.2]
  class Provider  < ApplicationRecord
    has_many :ethnicities, :class_name => 'ImportProviderEthnicites::ProviderEthnicity'
  end

  class ProviderEthnicity < ApplicationRecord; end
  
  ETHNICITIES = ['Caucasian','African American','Asian','Asian Indian','Chinese','Filipino','Hispanic','Japanese','Korean','Vietnamese','Pacific Islander','American Indian/Alaska Native','Native Hawaiian','Guamanian or Chamorrow','Samoan','Russian','Unknown','Refused','Other']

  def self.up
    transaction do
      Provider.all.each do |provider|
        ETHNICITIES.each do |ethnicity|
          provider.ethnicities.create :name => ethnicity
        end
      end
    end
  end

  def self.down
    ProviderEthnicity.where(:name => ETHNICITIES).destroy_all
  end
end
