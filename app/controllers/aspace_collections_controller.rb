class AspaceCollectionsController < ApplicationController
  def index
    @aspace_collections = AspaceCollection.all
    render json: @aspace_collections.each_with_object({}) { |ac, h| h[ac.id] = ac.name }
  end
end
