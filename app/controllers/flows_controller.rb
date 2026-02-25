class FlowsController < ApplicationController
  include JwtAuthenticatable

  # GET /flows
  def index
    flows = FlowStore.all
    render json: flows
  end

  # GET /flows/:id
  def show
    flow_data = FlowStore.find(params[:id])
    chain     = FlowChain.build(flow_data)
    render json: { id: params[:id], flow: flow_data, chain: chain }
  rescue FlowStore::FlowNotFound => e
    render json: { error: e.message }, status: :not_found
  end

  # POST /flows
  def create
    id        = params[:id]
    flow_data = params.require(:flow).to_unsafe_h

    FlowStore.create(id, flow_data)
    render json: { id: id, flow: flow_data }, status: :created
  rescue FlowStore::FlowAlreadyExists => e
    render json: { error: e.message }, status: :conflict
  rescue FlowStore::InvalidFlowData => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PUT/PATCH /flows/:id
  def update
    flow_data = sanitize_flow(params.require(:flow).to_unsafe_h)
    FlowStore.update(params[:id], flow_data)
    render json: { id: params[:id], flow: flow_data }
  rescue FlowStore::FlowNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue FlowStore::InvalidFlowData => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /flows/:id
  def destroy
    FlowStore.destroy(params[:id])
    head :no_content
  rescue FlowStore::FlowNotFound => e
    render json: { error: e.message }, status: :not_found
  end

  # POST /flows/copy
  def copy
    source_id = params[:source_id]
    dest_id   = params[:dest_id]

    FlowStore.copy(source_id, dest_id)
    render json: { id: dest_id }, status: :created
  rescue FlowStore::FlowNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue FlowStore::FlowAlreadyExists => e
    render json: { error: e.message }, status: :conflict
  rescue FlowStore::InvalidFlowData => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # Strip invalid fields from every non-START_NODE node based on command type.
  def sanitize_flow(flow_data)
    flow_data.each_with_object({}) do |(key, node), result|
      if key == "START_NODE" || !node.is_a?(Hash)
        result[key] = node
      else
        type = node["type"]
        result[key] = CommandSchema.known?(type) ? CommandSchema.sanitize(type, node) : node
      end
    end
  end
end

