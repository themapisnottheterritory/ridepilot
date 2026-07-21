# These settings are stored in the `settings` table in the
# database, but are also cached in tmp/cache. You can destroy
# them all using `ApplicationSetting.delete_all`, but you'll
# also want to `rails tmp:clear` to get rid of the cached values
require 'rails-settings-cached'
class ApplicationSetting < RailsSettings::Base
  cache_prefix { "v1" }

  # Define settings fields for rails-settings-cached 2.x API
  field :devise_password_archiving_count, type: :integer, default: 0
  field :devise_expire_password_after, default: false
  field :cad_avl_data_storage_months, type: :integer, default: 1
  field :cad_avl_gps_interval_seconds, type: :integer, default: 10
  field :cad_avl_cad_refresh_interval_seconds, type: :integer, default: 30
  field :opentransit_polling_interval_seconds, type: :integer, default: 15

  # For compatibility with older code expecting get_all method
  def self.get_all
    {
      'devise.password_archiving_count' => devise_password_archiving_count,
      'devise.expire_password_after' => devise_expire_password_after,
      'cad_avl.data_storage_months' => cad_avl_data_storage_months,
      'cad_avl.gps_interval_seconds' => cad_avl_gps_interval_seconds,
      'cad_avl.cad_refresh_interval_seconds' => cad_avl_cad_refresh_interval_seconds,
      'opentransit.polling_interval_seconds' => opentransit_polling_interval_seconds
    }
  end

  def self.update_settings(params)
    transaction do
      self.devise_password_archiving_count = params['devise.password_archiving_count'].to_i if params.has_key? "devise.password_archiving_count"

      if params.has_key? "devise.expire_password_after"
        expire_password_after = (params['devise.expire_password_after'] || 0).to_i
        # false means password_expirable is disabled
        self.devise_expire_password_after = (expire_password_after == 0) ? false : expire_password_after.days
      end

      # CAD/AVL settings
      self.cad_avl_data_storage_months = params['cad_avl.data_storage_months'].to_i if params.has_key? "cad_avl.data_storage_months"
      self.cad_avl_gps_interval_seconds = params['cad_avl.gps_interval_seconds'].to_i if params.has_key? "cad_avl.gps_interval_seconds"
      self.cad_avl_cad_refresh_interval_seconds = params['cad_avl.cad_refresh_interval_seconds'].to_i if params.has_key? "cad_avl.cad_refresh_interval_seconds"
      self.opentransit_polling_interval_seconds = params['opentransit.polling_interval_seconds'].to_i if params.has_key? "opentransit.polling_interval_seconds"

      return true
    end

    return false
  end

  def self.apply!
    Devise.expire_password_after    = self.devise_expire_password_after
    Devise.password_archiving_count = self.devise_password_archiving_count
    return true
  end
end
