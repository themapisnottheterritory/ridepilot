module ApplicationCable
  class Channel < ActionCable::Channel::Base
    # A view-only tablet (TabletView) hears everything the driver's does but
    # can't act: no chat sends, no emergency, no dismissing alerts.
    def perform_action(data)
      return if connection.view_only
      super
    end

    private

    # Who may listen to what (2026-10-01; until then any signed-in user or
    # tablet could subscribe to any agency's or driver's stream).
    #   office staff: any stream of an agency they have a role in (every
    #     agency for a system admin)
    #   a driver's tablet: its own driver's streams and its own runs only

    def staff_of?(provider_id)
      return false if provider_id.blank?
      current_user.super_admin? || current_user.roles.where(provider_id: provider_id.to_i).exists?
    end

    def own_driver
      return @own_driver if defined?(@own_driver)
      @own_driver = Driver.find_by(user_id: current_user.id)
    end

    # staff of the agency, or the driver themself
    def may_follow_driver?(provider_id, driver_id)
      return true if staff_of?(provider_id)
      own_driver.present? && own_driver.id == driver_id.to_i && own_driver.provider_id == provider_id.to_i
    end

    def may_follow_provider?(provider_id)
      staff_of?(provider_id) || (own_driver.present? && own_driver.provider_id == provider_id.to_i)
    end

    def may_follow_run?(run_id)
      run = Run.find_by(id: run_id)
      return false unless run
      staff_of?(run.provider_id) || (own_driver.present? && run.driver_id == own_driver.id)
    end
  end
end
