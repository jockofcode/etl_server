require "rails_helper"

RSpec.describe CommandSchema do
  describe ".all" do
    it "returns a hash with all 9 command types" do
      expect(CommandSchema.all.keys).to match_array(%w[
        transform_data check_data for_each_item
        respond_with_success respond_with_error
        send_to_url log_data
        return_data_to_iterator return_error_to_iterator
      ])
    end
  end

  describe ".for_type" do
    it "returns the schema for a known type" do
      schema = CommandSchema.for_type("log_data")
      expect(schema[:fields]).to have_key("input")
    end

    it "returns nil for an unknown type" do
      expect(CommandSchema.for_type("does_not_exist")).to be_nil
    end
  end

  describe ".valid_fields" do
    it "includes all declared fields plus 'type'" do
      fields = CommandSchema.valid_fields("send_to_url")
      expect(fields).to include("url", "method", "body", "headers", "output", "status_key", "next", "type")
    end

    it "always includes 'type'" do
      CommandSchema.all.each_key do |cmd_type|
        expect(CommandSchema.valid_fields(cmd_type)).to include("type")
      end
    end

    it "returns an empty array for unknown type" do
      expect(CommandSchema.valid_fields("bogus")).to eq([])
    end
  end

  describe ".sanitize" do
    it "strips fields not valid for the given type" do
      node = { "type" => "log_data", "input" => "hello", "url" => "http://bad.example.com", "extra" => "junk" }
      result = CommandSchema.sanitize("log_data", node)
      expect(result.keys).to contain_exactly("type", "input")
    end

    it "keeps all valid fields" do
      node = { "type" => "send_to_url", "url" => "http://example.com", "method" => "GET" }
      result = CommandSchema.sanitize("send_to_url", node)
      expect(result.keys).to contain_exactly("type", "url", "method")
    end

    it "is a no-op if all fields are valid" do
      node = { "type" => "log_data", "input" => "msg", "next" => "step2" }
      expect(CommandSchema.sanitize("log_data", node)).to eq(node)
    end
  end

  describe ".known?" do
    it "returns true for all 9 command types" do
      %w[transform_data check_data for_each_item respond_with_success respond_with_error
         send_to_url log_data return_data_to_iterator return_error_to_iterator].each do |type|
        expect(CommandSchema.known?(type)).to be true
      end
    end

    it "returns false for an unknown type" do
      expect(CommandSchema.known?("mystery_command")).to be false
    end
  end
end

