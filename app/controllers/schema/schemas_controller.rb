module Schema
  class SchemasController < ApplicationController
    include JwtAuthenticatable

    # GET /schema/commands
    def commands
      render json: CommandSchema.all
    end

    # GET /schema/transforms
    def transforms
      render json: TransformSchema.by_category
    end
  end
end

