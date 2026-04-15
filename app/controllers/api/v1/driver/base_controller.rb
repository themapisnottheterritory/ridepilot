class Api::V1::Driver::BaseController < Api::V2::BaseController
  before_action :driver_required

  attr_reader :driver

  protected

  # Actions to take after successfully authenticated a user token.
  # This is run automatically on successful token authentication
  def after_successful_token_authentication
    set_driver
  end

  def set_driver
    @driver = Driver.find_by(user_id: current_user.try(:id))
  end

  # Renders a 401 failure response if driver authentication was not successful
  def driver_required
    render_failed_driver_auth_response unless @driver.present?
  end

  # Renders a failed driver auth response
  def render_failed_driver_auth_response
    render status: 401,
      json: json_response(:fail, data: {user: "User is not a driver."})
  end

  # Renders a successful response, passing along a given object as data
  def success_response(data={}, opts={})
    status = 200

    json_response = {}

    if data.is_a?(ActiveRecord::Relation)
      json_response = package_collection(data, opts)
    elsif data.is_a?(Array)
      json_response = package_array(data, opts)
    elsif data.is_a?(ActiveRecord::Base)
      json_response = package_record(data, opts)
    else
      json_response = data
    end

    json_response[:status] = "success"

    {
      status: status,
      json: json_response
    }
  end

  def package_collection(collection, opts = {})
    serializer = "#{collection.klass.name}Serializer".safe_constantize
    opts[:meta] = { total: collection.size }
    serializer.new(collection, opts).serializable_hash if serializer
  end

  def package_array(array, opts = {})
    if array && array.size > 0
      serializer = "#{array.first.class.name}Serializer".safe_constantize
      opts[:meta] = { total: array.size }
      serializer.new(array, opts).serializable_hash if serializer
    else
      {data: []}
    end
  end

  def package_record(record, opts={})
    serializer = "#{record.class.name}Serializer".safe_constantize
    serializer.new(record, opts).serializable_hash if serializer
  end
end
