require "rails_helper"

RSpec.describe NasCopyJob, type: :job do
  let!(:user) do
    create(:user,
           email: "nas-copy-job@example.com",
           password: "password123",
           password_confirmation: "password123",
           username: "nas-copy-job-user")
  end

  let!(:source_account) { create(:nas_account, user: user, username: "source-user", plain_password: "source-pass") }
  let!(:destination_account) { create(:nas_account, user: user, username: "dest-user", plain_password: "dest-pass") }

  it "stages NAS-to-NAS copies through a temporary local file" do
    transfer = NasCopyTransfer.create!(
      user: user,
      nas_account: destination_account,
      source_nas_account: source_account,
      source_nas_path: "reports/quarterly.csv",
      local_path: "reports/quarterly.csv",
      nas_path: "archive/2026",
      nas_filename: "quarterly.csv",
      status: "queued"
    )

    get_args = nil
    put_args = nil

    allow(SmbClient).to receive(:get) do |**kwargs|
      get_args = kwargs
      File.write(kwargs[:local_path], "staged")
      { success: true }
    end
    allow(SmbClient).to receive(:put) do |**kwargs|
      put_args = kwargs
      { success: true }
    end

    described_class.perform_now(transfer.id)

    expect(get_args).to include(
      share: "source-user",
      remote_path: "reports/quarterly.csv",
      username: "source-user",
      password: "source-pass",
      timeout: described_class::NAS_COPY_TIMEOUT
    )
    expect(File.basename(get_args[:local_path])).to eq("quarterly.csv")

    expect(put_args).to include(
      share: "dest-user",
      remote_path: "archive/2026",
      nas_filename: "quarterly.csv",
      username: "dest-user",
      password: "dest-pass",
      timeout: described_class::NAS_COPY_TIMEOUT
    )
    expect(put_args[:local_path]).to eq(get_args[:local_path])
    expect(transfer.reload.status).to eq("done")
  end
end
