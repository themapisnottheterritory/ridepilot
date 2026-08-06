#-------------------------------------------------------------------------------
#
# TripDistanceDurationProxy
#
# Proxy for getting the travel time & distance from point A to point B relying on proxy
#    service
#
#-------------------------------------------------------------------------------
class TripDistanceDurationProxy

  attr_reader :proxy

  # Define on self, since it's  a class method
  def method_missing(method_sym, *arguments)

    # see if the adapter responds to the method call
    if method_sym.to_s =~ /^get_(.*)$/
      method_object = proxy.method(method_sym)
      method_object.call(*arguments)
    else
      super
    end
  end

  # It's important to know Object defines respond_to to take two parameters: the method to check, and whether to include private methods
  # http://www.ruby-doc.org/core/classes/Object.html#M000333
  def respond_to?(method_sym, include_private = false)
    if method_sym.to_s =~ /^get_(.*)$/
      proxy.respond_to? method_sym
    else
      super
    end
  end

  def initialize(proxy_type, params = {})
    proxy_type = proxy_type.try(:upcase)
    if proxy_type == 'GOOGLE'
      @proxy = GoogleDistanceDurationService.new(params[:from_lat], params[:from_lon], params[:to_lat], params[:to_lon], params[:trip_datetime])
    elsif proxy_type == 'OTP'
      @proxy = OtpDistanceDurationService.new(params[:from_lat], params[:from_lon], params[:to_lat], params[:to_lon], params[:trip_datetime])
    elsif proxy_type == 'OSRM'
      @proxy = OsrmDistanceDurationService.new(params[:from_lat], params[:from_lon], params[:to_lat], params[:to_lon], params[:trip_datetime])
    else
      raise "Proxy #{proxy_type} not found."
    end
  end
end
