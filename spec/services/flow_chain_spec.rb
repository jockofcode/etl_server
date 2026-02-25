require "rails_helper"

RSpec.describe FlowChain do
  describe ".build" do
    context "with a linear flow" do
      let(:flow_data) do
        {
          "START_NODE" => { "name" => "Linear", "next" => "step1" },
          "step1"      => { "type" => "log_data",  "input" => "a", "next" => "step2" },
          "step2"      => { "type" => "log_data",  "input" => "b", "next" => "step3" },
          "step3"      => { "type" => "respond_with_success" }
        }
      end

      it "returns the entry_node key" do
        result = FlowChain.build(flow_data)
        expect(result[:entry_node]).to eq("step1")
      end

      it "builds a chain with all steps in order" do
        result = FlowChain.build(flow_data)
        keys = result[:chain].map { |s| s[:key] }
        expect(keys).to eq(%w[step1 step2 step3])
      end

      it "produces empty branches for linear nodes" do
        result = FlowChain.build(flow_data)
        result[:chain].each do |step|
          expect(step[:branches]).to be_empty
        end
      end
    end

    context "with a check_data fork" do
      let(:flow_data) do
        {
          "START_NODE" => { "name" => "Fork", "next" => "check" },
          "check"      => { "type" => "check_data", "input" => "{{x}}", "check" => { "type" => "exists" }, "on_success" => "ok_node", "on_failure" => "err_node" },
          "ok_node"    => { "type" => "respond_with_success" },
          "err_node"   => { "type" => "respond_with_error" }
        }
      end

      it "includes on_success and on_failure branches" do
        result = FlowChain.build(flow_data)
        check_step = result[:chain].find { |s| s[:key] == "check" }

        expect(check_step[:branches][:on_success]).to be_an(Array)
        expect(check_step[:branches][:on_success].first[:key]).to eq("ok_node")

        expect(check_step[:branches][:on_failure]).to be_an(Array)
        expect(check_step[:branches][:on_failure].first[:key]).to eq("err_node")
      end

      it "does not follow next for check_data nodes" do
        result = FlowChain.build(flow_data)
        keys = result[:chain].map { |s| s[:key] }
        expect(keys).to eq(%w[check])
      end
    end

    context "with a for_each_item iterator" do
      let(:flow_data) do
        {
          "START_NODE"    => { "name" => "Iterator", "next" => "each" },
          "each"          => { "type" => "for_each_item", "input" => "{{list}}", "iterator" => "iter_step", "next" => "done" },
          "iter_step"     => { "type" => "return_data_to_iterator", "data" => "{{item}}" },
          "done"          => { "type" => "respond_with_success" }
        }
      end

      it "includes an iterator branch" do
        result = FlowChain.build(flow_data)
        each_step = result[:chain].find { |s| s[:key] == "each" }
        expect(each_step[:branches][:iterator]).to be_an(Array)
        expect(each_step[:branches][:iterator].first[:key]).to eq("iter_step")
      end

      it "continues the main chain after the for_each_item node" do
        result = FlowChain.build(flow_data)
        keys = result[:chain].map { |s| s[:key] }
        expect(keys).to include("each", "done")
      end
    end

    context "with a missing START_NODE next" do
      let(:flow_data) { { "START_NODE" => { "name" => "Empty" } } }

      it "returns an empty chain" do
        result = FlowChain.build(flow_data)
        expect(result[:chain]).to eq([])
      end
    end

    context "with a cycle" do
      let(:flow_data) do
        {
          "START_NODE" => { "name" => "Cyclic", "next" => "a" },
          "a" => { "type" => "log_data", "input" => "x", "next" => "b" },
          "b" => { "type" => "log_data", "input" => "y", "next" => "a" }
        }
      end

      it "does not loop infinitely" do
        expect { FlowChain.build(flow_data) }.not_to raise_error
      end
    end
  end
end

