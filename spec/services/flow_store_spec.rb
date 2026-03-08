require "rails_helper"

RSpec.describe FlowStore do
  let(:tmp_dir) { Dir.mktmpdir("flow_store_spec") }

  before do
    stub_const("FlowStore::FLOWS_DIR", tmp_dir)
  end

  after do
    FileUtils.remove_entry(tmp_dir)
  end

  let(:valid_flow) do
    {
      "START_NODE" => { "name" => "My Flow", "description" => "A test flow", "next" => "step1" },
      "step1"      => { "type" => "log_data", "input" => "hello" }
    }
  end

  describe ".all" do
    it "returns an empty array when no flows exist" do
      expect(FlowStore.all).to eq([])
    end

    it "returns summaries for each flow file" do
      FlowStore.create("my-flow", valid_flow)
      result = FlowStore.all
      expect(result.length).to eq(1)
      expect(result.first[:id]).to eq("my-flow")
      expect(result.first[:name]).to eq("My Flow")
    end
  end

  describe ".find" do
    it "returns parsed flow data for an existing flow" do
      FlowStore.create("my-flow", valid_flow)
      result = FlowStore.find("my-flow")
      expect(result["START_NODE"]["name"]).to eq("My Flow")
    end

    it "raises FlowNotFound for a missing flow" do
      expect { FlowStore.find("nonexistent") }.to raise_error(FlowStore::FlowNotFound)
    end
  end

  describe ".create" do
    it "creates a new flow file" do
      FlowStore.create("new-flow", valid_flow)
      expect(File.exist?(File.join(tmp_dir, "new-flow.yml"))).to be true
    end

    it "raises FlowAlreadyExists if id is taken" do
      FlowStore.create("dup-flow", valid_flow)
      expect { FlowStore.create("dup-flow", valid_flow) }.to raise_error(FlowStore::FlowAlreadyExists)
    end

    it "raises InvalidFlowData for a bad id" do
      expect { FlowStore.create("Bad ID!", valid_flow) }.to raise_error(FlowStore::InvalidFlowData)
    end

    it "raises InvalidFlowData for an id containing underscores" do
      expect { FlowStore.create("bad_id", valid_flow) }.to raise_error(FlowStore::InvalidFlowData)
    end

    it "raises InvalidFlowData for an id starting with a hyphen" do
      expect { FlowStore.create("-bad", valid_flow) }.to raise_error(FlowStore::InvalidFlowData)
    end

    it "raises InvalidFlowData for an id ending with a hyphen" do
      expect { FlowStore.create("bad-", valid_flow) }.to raise_error(FlowStore::InvalidFlowData)
    end

    it "raises InvalidFlowData when START_NODE is missing" do
      expect { FlowStore.create("no-start", { "step1" => {} }) }.to raise_error(FlowStore::InvalidFlowData)
    end

    it "raises InvalidFlowData when START_NODE has no name" do
      bad = { "START_NODE" => { "description" => "oops" } }
      expect { FlowStore.create("bad-start", bad) }.to raise_error(FlowStore::InvalidFlowData)
    end
  end

  describe ".update" do
    it "overwrites an existing flow" do
      FlowStore.create("updatable", valid_flow)
      updated = valid_flow.merge("START_NODE" => valid_flow["START_NODE"].merge("name" => "Updated"))
      FlowStore.update("updatable", updated)
      expect(FlowStore.find("updatable")["START_NODE"]["name"]).to eq("Updated")
    end

    it "raises FlowNotFound for a missing flow" do
      expect { FlowStore.update("ghost", valid_flow) }.to raise_error(FlowStore::FlowNotFound)
    end
  end

  describe ".destroy" do
    it "removes the flow file" do
      FlowStore.create("deletable", valid_flow)
      FlowStore.destroy("deletable")
      expect { FlowStore.find("deletable") }.to raise_error(FlowStore::FlowNotFound)
    end

    it "raises FlowNotFound for a missing flow" do
      expect { FlowStore.destroy("ghost") }.to raise_error(FlowStore::FlowNotFound)
    end
  end

  describe ".copy" do
    it "duplicates the flow under a new id" do
      FlowStore.create("original", valid_flow)
      FlowStore.copy("original", "copy-of-original")
      expect(FlowStore.find("copy-of-original")["START_NODE"]["name"]).to eq("My Flow")
    end

    it "raises FlowNotFound when source does not exist" do
      expect { FlowStore.copy("ghost", "dest") }.to raise_error(FlowStore::FlowNotFound)
    end

    it "raises FlowAlreadyExists when dest id is taken" do
      FlowStore.create("source", valid_flow)
      FlowStore.create("dest", valid_flow)
      expect { FlowStore.copy("source", "dest") }.to raise_error(FlowStore::FlowAlreadyExists)
    end

    it "raises InvalidFlowData for an invalid dest id" do
      FlowStore.create("source", valid_flow)
      expect { FlowStore.copy("source", "BAD ID") }.to raise_error(FlowStore::InvalidFlowData)
    end
  end
end

