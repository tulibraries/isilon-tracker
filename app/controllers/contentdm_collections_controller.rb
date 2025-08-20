class ContentdmCollectionsController < ApplicationController
  def index
    @cdm_collections = ContentdmCollection.all
    render json: @cdm_collections.each_with_object({}) { |cc, h| h[cc.id] = cc.name }
  end
end
