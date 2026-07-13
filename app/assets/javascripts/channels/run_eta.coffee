App.run_eta_channels ||= {}

App.create_run_eta_channel = (run_id) ->
  return if App.run_eta_channels[run_id]

  App.run_eta_channels[run_id] = App.cable.subscriptions.create {
      channel: "RunEtaChannel",
      run_id: run_id
    },
    connected: ->
      console.log("RunEtaChannel connected for run #{run_id}")

    disconnected: ->
      console.log("RunEtaChannel disconnected for run #{run_id}")

    received: (data) ->
      return unless data.ordered_trip_ids && data.etas

      # Update ETA cells in the dispatch manifest table
      run_panel = $("#run_trips_panel_" + run_id)
      if run_panel.length
        for trip_id, i in data.ordered_trip_ids
          eta_seconds = data.etas[i]
          eta_date = new Date(eta_seconds * 1000)
          eta_text = eta_date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })

          # Find the pickup row for this trip and update ETA
          row = run_panel.find("tr[data-trip-id='" + trip_id + "'][data-leg-flag='1']")
          if row.length
            row.find('td.itinerary_eta').text(eta_text).addClass('eta-updated')

        # Flash effect to show update
        run_panel.find('.eta-updated').each ->
          el = $(this)
          el.css('background-color', '#d4edda')
          setTimeout (-> el.css('background-color', '')), 2000

      # Update client portal ETA if present
      portal = $(".client-portal")
      if portal.length
        trip_id = parseInt(portal.data('trip-id'))
        idx = data.ordered_trip_ids.indexOf(trip_id)
        if idx >= 0
          eta_seconds = data.etas[idx]
          eta_date = new Date(eta_seconds * 1000)
          eta_el = document.getElementById('eta-time')
          if eta_el
            eta_el.textContent = eta_date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })

App.destroy_run_eta_channel = (run_id) ->
  if App.run_eta_channels[run_id]
    App.run_eta_channels[run_id].unsubscribe()
    delete App.run_eta_channels[run_id]
