require "rails_helper"

RSpec.describe TransformSchema do
  describe ".all" do
    it "returns a hash of all transform types" do
      expect(TransformSchema.all).to be_a(Hash)
      expect(TransformSchema.all.keys).to include("add", "concatenate", "map_get", "base64_encode", "current_date")
    end
  end

  describe ".for_type" do
    it "returns the schema for a known transform" do
      schema = TransformSchema.for_type("add")
      expect(schema[:category]).to eq("math")
      expect(schema[:fields]).to have_key("value")
    end

    it "returns nil for an unknown transform" do
      expect(TransformSchema.for_type("nonexistent")).to be_nil
    end
  end

  describe ".valid_fields" do
    it "includes all declared fields plus 'type'" do
      fields = TransformSchema.valid_fields("replace_text")
      expect(fields).to include("search", "replace", "type")
    end

    it "returns only 'type' for field-less transforms" do
      expect(TransformSchema.valid_fields("upper_case")).to eq(%w[type])
    end

    it "returns empty array for unknown type" do
      expect(TransformSchema.valid_fields("bogus")).to eq([])
    end
  end

  describe ".sanitize" do
    it "strips invalid fields" do
      data = { "type" => "add", "value" => 5, "invalid_field" => "x" }
      result = TransformSchema.sanitize("add", data)
      expect(result.keys).to contain_exactly("type", "value")
    end

    it "is a no-op when all fields are valid" do
      data = { "type" => "split_text", "delimiter" => "," }
      expect(TransformSchema.sanitize("split_text", data)).to eq(data)
    end
  end

  describe ".known?" do
    it "returns true for known transforms" do
      %w[add subtract equal_to concatenate count map_get boolean base64_encode current_date].each do |t|
        expect(TransformSchema.known?(t)).to be true
      end
    end

    it "returns false for unknown transforms" do
      expect(TransformSchema.known?("fly_to_moon")).to be false
    end
  end

  describe ".by_category" do
    it "returns a hash keyed by category name" do
      result = TransformSchema.by_category
      expect(result.keys).to include("math", "logic", "text", "lists", "maps", "type_conversions", "dates", "encoding")
    end

    it "groups math transforms under math key" do
      result = TransformSchema.by_category
      expect(result["math"].keys).to include("add", "subtract", "multiply")
    end

    it "groups encoding transforms under encoding key" do
      result = TransformSchema.by_category
      expect(result["encoding"].keys).to include("base64_encode", "json_decode")
    end
  end
end

