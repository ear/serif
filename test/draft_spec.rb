require "test_helper"

describe Serif::Draft do
  before :all do
    @site = Serif::Site.new(testing_dir)
    D = Serif::Draft
    FileUtils.rm_rf(testing_dir("_trash"))
  end

  describe "#delete!" do
    it "moves the file to _trash" do
      draft = D.new(@site)
      draft.slug = "test-draft"
      draft.title = "Some draft title"
      draft.save("some content")
      draft.delete!
      Dir[testing_dir("_trash/*-test-draft")].length.should == 1
    end

    it "creates the _trash directory if it doesn't exist" do
      FileUtils.rm_rf(testing_dir("_trash"))

      draft = D.new(@site)
      draft.slug = "test-draft"
      draft.title = "Some draft title"
      draft.save("some content")
      draft.delete!

      File.exist?(testing_dir("_trash")).should be_true
    end
  end

  describe "#save" do
    it "saves the file to _drafts" do
      draft = D.new(@site)
      draft.slug = "test-draft"
      draft.title = "Some draft title"

      D.exist?(@site, draft.slug).should be_false
      File.exist?(testing_dir("_drafts/test-draft")).should be_false
      
      draft.save("some content")

      D.exist?(@site, draft.slug).should be_true
      File.exist?(testing_dir("_drafts/test-draft")).should be_true

      # clean up the file
      draft.delete!
    end
  end
end