module ApplicationCable
  class Channel < ActionCable::Channel::Base
    # A view-only tablet (TabletView) hears everything the driver's does but
    # can't act: no chat sends, no emergency, no dismissing alerts.
    def perform_action(data)
      return if connection.view_only
      super
    end
  end
end
