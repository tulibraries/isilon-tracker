class IsilonFoldersController < ApplicationController
  def index
    @isilon_folders = IsilonFolder.all
  end

  def show
    @isilon_folder = IsilonFolder.find(params[:id])

    respond_to do |format|
      format.html { redirect_to root_path }
      format.json { render json: @isilon_folder, serializer: IsilonFolderSerializer }
    end
  end
end
