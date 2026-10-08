module ApplicationHelper  
  def current_provider
    current_user.try(:current_provider)
  end

  def current_provider_id
    current_provider.try(:id)
  end

  def show_dispatch?
    current_user && current_provider && current_provider.dispatch?
  end
  
  def show_scheduling?
    current_user && current_provider.scheduling?
  end

  # Next Bus tab: agencies that run fixed routes (GCRPC's Victoria Transit);
  # NEXT_BUS_PROVIDER_IDS="1,143" would add Lavaca, e.g. if its CSRs take
  # Victoria calls
  NEXT_BUS_PROVIDER_IDS = ENV.fetch("NEXT_BUS_PROVIDER_IDS", "1").split(",").map(&:to_i).freeze
  def show_next_bus?
    show_scheduling? && NEXT_BUS_PROVIDER_IDS.include?(current_provider&.id)
  end

  def is_admin_or_system_admin?
    current_user.present? && (current_user.admin? || current_user.super_admin?)
  end
  
  def new_device_pool_members_options(members)
    options_for_select [["",""]] + members.map { |d| [d.name, d.id] }
  end
  
  def display_trip_result(trip_result)
    trip_result.try(:name) || "Pending"
  end

  def format_full_datetime(time)
    time.strftime "%l:%M%P %a %d-%b-%Y" if time
  end

  def format_simple_full_datetime(time)
    time.strftime "%B %d, %Y %I:%M %p" if time
  end
  
  def format_time_for_listing(time)
    time.strftime('%l:%M%P') if time
  end

  def format_time_for_listing_day(time)
    time.strftime('%a %b %d, %Y') if time
  end

  def format_time_as_title_for_listing_day(time)
    time.strftime('%b %d, %Y') if time
  end

  def format_date(time, format = 'us')
    time.strftime('%m/%d/%Y') if time
  end
  
  def format_date_for_daily_manifest(date)
    date.strftime('%A, %v') if date
  end

  def format_for_pdf_printing(datetime)
    datetime.strftime(" %m/%d/%Y @ %k:%M")
  end

  def format_float_number(number, precision = 2)
    number_with_precision(number, precision: precision, strip_insignificant_zeros: true)
  end

  def delete_trippable_link(trippable)
    if can? :destroy, trippable
      # "delete": application.js opens the confirm / merge dialog from it. Restyled
      # to btn-danger alone in 2018, the click went straight to a GET of the
      # address, which has no route ("No route matches", Phil 2026-10-08).
      link_to trippable.trips.present? ? translate_helper("merge") : translate_helper("delete"), trippable, :class => 'btn btn-danger delete'
    end
  end
  
  def can_delete?(trippable)
    trippable.trips.blank? && can?( :destroy, trippable )
  end
  
  def format_newlines(text)
    return text.gsub("\n", "<br/>")
  end

  def bodytag_class
    a = controller.controller_name.underscore
    b = controller.action_name.underscore
    "#{a} #{b}".gsub(/_/, '-')
  end

  def collect_weekdays(schedule)
    weekdays = []
    if schedule.monday
      weekdays.push :monday
    end
    if schedule.tuesday
      weekdays.push :tuesday
    end
    if schedule.wednesday
      weekdays.push :wednesday
    end
    if schedule.thursday
      weekdays.push :thursday
    end
    if schedule.friday
      weekdays.push :friday
    end
    if schedule.saturday
      weekdays.push :saturday
    end
    if schedule.sunday
      weekdays.push :sunday
    end
    return weekdays
  end

  def weekday_abbrev(weekday)
    weekday_abbrevs = {
      :monday => 'M',
      :tuesday => 'T',
      :wednesday => 'W',
      :thursday => 'R',
      :friday => 'F',
      :saturday => 'S',
      :sunday => 'U'
    }

    return weekday_abbrevs[weekday]
  end

  def is_add_user_allowed?(user)
    user.present? && ( user.admin? || user.super_admin?)
  end

  def add_tooltip(key)
    if TranslationEngine.translation_exists?(key)
      html = '<i class="fa fa-question-circle fa-2x pull-right label-help" style="margin-top:-4px;" title data-content="'
      html << TranslationEngine.translate_text(key.to_sym)
      html << '" aria-label="'
      html << TranslationEngine.translate_text(key.to_sym)
      html << '" tabindex="0"></i>'
      return html.html_safe
    end
  end

  def reimbursement_cost_for_trips(provider, trips)
    number_to_currency ReimbursementRateCalculator.new(provider).total_reimbursement_due_for_trips(trips)
  end


  def can_access_admin_tab(a_user)
    a_user && a_user.super_admin?
  end

  def can_access_provider_settings_tab(a_user, a_provider)
    a_user && a_user.admin? && can?(:read, a_provider)
  end

  def display_linked_trip_info(trip)
    linking_to_text = translate_helper(:linking_to)
    if trip.is_return?
      trip.outbound_trip ? "<a href='#{trip_path(trip.outbound_trip)}'>#{linking_to_text}: #{trip.outbound_trip.id}</a>" : ""
    else
      trip.return_trip ? "<a href='#{trip_path(trip.return_trip)}'>#{linking_to_text}: #{trip.return_trip.id}</a>" : ""
    end
  end

  def format_phone_number(phone_number)
    return "" if phone_number.blank?

    us_phony = Phony['1'] # US phone validation

    norm_number = us_phony.normalize(phone_number.to_s)

    number_to_phone norm_number, area_code: true
  end

  def show_provider_setting_alert(provider, section)
    return unless provider && !section.blank?

    has_alert = case section
    when 'general'
      provider.operating_hours.empty?
    when 'users'
      provider.roles.empty?
    when 'drivers'
      provider.drivers.empty?
    when 'vehicles'
      provider.vehicles.empty? || VehicleType.for_provider(provider.id).empty?
    when 'addresses'
      ProviderCommonAddress.where(provider: provider).empty?
    when 'customers'
      Customer.for_provider(provider.try(:id)).empty?
    end

    if has_alert
      "<div class='pull-right'><i style='color: red;' class='fa fa-exclamation-triangle'></i></div>".html_safe
    end
  end

  def get_vehicle_warnings(vehicle, run = nil)
    class_name = ''
    warning_msg = ''
    overdue_msg = ''

    unless vehicle
      class_name = "overdue-danger"
      warning_msg = "No vehicle assigned."
    else
      if run && run.date && !vehicle.active_for_date?(run.date)
        class_name = "overdue-danger"
        warning_msg = "Inactive for the run date."
      end
      
      tips = []

      if vehicle.vehicle_compliances.legal.overdue.any?
        tips << "legal requirement"
        class_name = 'overdue-danger'
      end

      if vehicle.vehicle_maintenance_compliances.has_overdue?
        tips << "maintenance compliance"
        class_name = 'overdue-warning' if class_name.blank?
      end

      if vehicle.vehicle_compliances.non_legal.overdue.any?
        tips << "compliance event"
        class_name = 'overdue-warning' if class_name.blank?
      end

      if vehicle.expired?
        tips << "warranty"
        class_name = 'overdue-warning' if class_name.blank?
      end

      overdue_msg = "Overdue: " + tips.join(', ') if tips.any?
    
    end

    tips = warning_msg ? warning_msg + " " + overdue_msg.to_s : overdue_msg.to_s
    {
      class_name: class_name,
      tips: tips.blank? ? nil : tips
    }
  end 

  def get_driver_warnings(driver, run = nil)
    class_name = ''
    warning_msg = ''
    overdue_msg = ''
    
    unless driver 
      class_name = "overdue-danger"
      warning_msg = "No driver assigned."
    else 
      if run && run.date
        if !driver.active_for_date?(run.date)
          class_name = "overdue-danger"
          warning_msg = "Inactive for the run date. "
        elsif run.scheduled_start_time && run.scheduled_end_time
          unless driver.available_between?(run.date, run.scheduled_start_time, run.scheduled_end_time)
            class_name = "overdue-danger"
            warning_msg += "Unavailable for the whole run time range. "
          end
        elsif 
          unless driver.available?(run.date)
            class_name = "overdue-danger"
            warning_msg += "Unavailable for the run time. "
          end
        end
      end

      tips = []
      
      if driver.driver_compliances.legal.overdue.any?
        tips << "legal requirement"
        class_name = 'overdue-danger'
      end

      if driver.driver_compliances.non_legal.overdue.any?
        tips << "compliance event"
        class_name = 'overdue-warning' if class_name.blank?
      end

      overdue_msg = "Overdue: " + tips.join(', ') if tips.any?
    end

    tips = warning_msg ? warning_msg + " " + overdue_msg.to_s : overdue_msg.to_s
    {
      class_name: class_name,
      tips: tips.blank? ? nil : tips
    }
  end 

  def check_if_verify_client_code(customer)
    customer && !customer.code.blank? && session["client_code_#{customer.id}"] != '1'
  end

  def format_driver_emergency_contact(contact)
    return "" unless contact 

    parts = []
    name_part = "#{contact.name}"
    name_part += " (#{contact.relationship})" unless contact.relationship.blank?
    parts << name_part
    parts << format_phone_number(contact.phone_number) unless contact.phone_number.blank?
    parts << contact.geocoded_address.try(:one_line_text) if contact.geocoded_address

    parts.join("\n")
  end

  def run_cancel_warning(run)
    "Are you sure you want to cancel #{run.name}? Doing this will move any scheduled trips to the Unscheduled queue and cannot be undone."
  end

end
