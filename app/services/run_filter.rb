class RunFilter 

  attr_reader :runs, :filters

  def initialize(runs, filters = {})
    @runs = runs
    @filters = filters
  end

  def filter!
    filter_by_pickup_time!
    filter_by_days_of_week!
    filter_by_vehicle!
    filter_by_driver!
    filter_by_result!
    filter_by_service_mode!

    @runs
  end

  private 

  def filter_by_pickup_time!
    utility = Utility.new
    t_start = utility.parse_date(@filters[:start]) 
    t_end = utility.parse_date(@filters[:end]) 

    if !t_start && !t_end
      time    = Time.current
      t_start = time.to_date.in_time_zone
      t_end   = t_start
    elsif !t_end
      t_end   = t_start
    elsif !t_start
      t_start   = t_end
    end
    
    @runs = @runs.
      where("date >= '#{t_start.strftime "%Y-%m-%d"}'").
      where("date <= '#{t_end.strftime "%Y-%m-%d"}'").order(:date)
    
    @filters[:start] = t_start.to_i
    @filters[:end] = t_end.to_i
  end

  def filter_by_days_of_week!
    days_of_week = @filters[:days_of_week].blank? ? "0,1,2,3,4,5,6" : @filters[:days_of_week]
    @runs = @runs.where('extract(dow from date) in (?)', days_of_week.split(','))
    @filters[:days_of_week] = days_of_week
  end

  def filter_by_vehicle!
    if @filters[:vehicle_id].present?  
      @runs = @runs.includes(:vehicle).references(:vehicle).where(vehicle_id: @filters[:vehicle_id]) 
    end
  end

  def filter_by_driver!
    if @filters[:driver_id].present?  
      @runs = @runs.includes(:driver).references(:driver).where(driver_id: @filters[:driver_id]) 
    end
  end

  def filter_by_service_mode!
    if @filters[:service_mode].present? && Run::SERVICE_MODES.include?(@filters[:service_mode])
      @runs = @runs.where(service_mode: @filters[:service_mode])
    end
  end

  def filter_by_result!
    if @filters[:run_result_id].present?  
      if @filters[:run_result_id].to_i == 1 # Completed
        @runs = @runs.where(complete: true)
      else
        @runs = @runs.where(complete: false)
      end
    end
  end

end