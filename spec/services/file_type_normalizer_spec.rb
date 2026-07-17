require "rails_helper"

RSpec.describe FileTypeNormalizer do
  describe ".canonical" do
    subject(:canonical) do
      described_class.canonical(value)
    end

    context "with a normal extension" do
      let(:value) { "pdf" }

      it { is_expected.to eq("pdf") }
    end

    context "with uppercase characters and whitespace" do
      let(:value) { "  PDF  " }

      it { is_expected.to eq("pdf") }
    end

    context "with a leading period" do
      let(:value) { ".PDF" }

      it { is_expected.to eq("pdf") }
    end

    context "with a MIME type" do
      let(:value) { "application/pdf" }

      it { is_expected.to eq("pdf") }
    end

    context "with a MIME type containing parameters" do
      let(:value) { "application/pdf; charset=binary" }

      it { is_expected.to eq("pdf") }
    end

    context "with another valid MIME subtype" do
      let(:value) { "image/tiff" }

      it { is_expected.to eq("tiff") }
    end

    context "with pdfpage" do
      let(:value) { "pdfpage" }

      it { is_expected.to eq("pdfpage") }
    end

    context "with a subtype longer than four characters" do
      let(:value) { "application/octet-stream" }

      it { is_expected.to be_nil }
    end

    context "with an invalid long value" do
      let(:value) { "some-invalid-file-type" }

      it { is_expected.to be_nil }
    end

    context "with a blank value" do
      let(:value) { " " }

      it { is_expected.to be_nil }
    end

    context "with nil" do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end
  end
end
