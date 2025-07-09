module Admin
  class VolumesController < Administrate::ApplicationController
    def file_tree
      volume = Volume.find(params[:id])
      root_folders = volume.isilon_folders.where(parent_folder_id: nil)
      render json: root_folders, each_serializer: IsilonFolderSerializer
    end

    def show
      @volume = Volume.find(params[:id])
      super
    end
  end
end
