App.chats ||= App.chats || {}

@create_chat_channel = (provider_id, driver_id, new_message_callback) ->
  App.chats[[provider_id, driver_id]] = App.cable.subscriptions.create {
      channel: "ChatChannel",
      provider_id: provider_id,
      driver_id: driver_id
    },
    connected: ->
      # Called when the subscription is ready for use on the server

    disconnected: ->
      # Called when the subscription has been terminated by the server

    received: (data) ->
      # the driver read our messages; "SeenByDispatch" is for the tablet
      if data.action == 'SeenByDriver'
        window.chat_seen_by_driver(data) if window.chat_seen_by_driver
      else if data.action == 'CreateMessage' || !data.action
        new_message_callback(data.id) if new_message_callback

    create: (message) ->
      @perform 'create', body: message, driver_id: driver_id