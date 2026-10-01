show_emergency_alert_dialog = (id, provider_id, message) ->
  # staff pages: a banner that stays and sounds until "Got it!" (dispatch_desk.js)
  if window.DispatchDeskEmergency
    return window.DispatchDeskEmergency.show(id, message)
  bootbox.alert
    className: "emergency_alert_" + id
    backdrop: false
    onEscape: false
    title: '<span style=\'color:red;\'><i class="fa fa-2x fa-exclamation-triangle"></i> Emergency Alert</span>'
    size: 'large'
    message: '<b>' + message + "</b>"
    buttons: ok:
      label: 'Got it!'
      className: 'btn-success'
    callback: ->
      if App.alerts[provider_id]
        App.alerts[provider_id].dismiss(id, current_user_id)

App.alerts ||= App.alerts || {}

create_alert_channel = (provider_id) ->
  App.alerts[provider_id] = App.cable.subscriptions.create {
      channel: "AlertChannel",
      provider_id: provider_id
    },
    connected: ->
      # Called when the subscription is ready for use on the server

    disconnected: ->
      # Called when the subscription has been terminated by the server

    received: (data) ->
      # Called when there's incoming data on the websocket for this channel
      if data.dismiss
        $(".emergency_alert_" + data.id).hide();
        window.DispatchDeskEmergency.drop(data.id) if window.DispatchDeskEmergency
      else
        show_emergency_alert_dialog(data.id, data.provider_id, data.message);

    trigger: ->
      @perform 'trigger'

    dismiss: (id, reader_id) ->
      @perform 'dismiss', id: id, reader_id: reader_id

$ ->
  if typeof current_provider_id != "undefined" 
    create_alert_channel current_provider_id
  