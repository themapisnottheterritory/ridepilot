# GET /trouble_board -- GCRPC I.T.'s view of where RidePilot is getting in
# people's way (TroubleBoard, TroubleWatch). System admins and the I.T.
# addresses only.
class TroubleBoardController < ApplicationController
  def index
    raise CanCan::AccessDenied unless TroubleWatch.can_view?(current_user)
    @providers = Provider.order(:name).pluck(:name, :id)
    @board = TroubleBoard.new(days: params[:days] || 7, provider_id: params[:provider_id])
  end
end
