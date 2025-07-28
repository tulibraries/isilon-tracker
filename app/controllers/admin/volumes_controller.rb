module Admin
  class VolumesController < Administrate::ApplicationController
    def show
      @volume = Volume.find(params[:id])
      super
    end
  end
end
