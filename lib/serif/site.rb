class StandardFilterCheck
  include Liquid::StandardFilters

  def date_supports_now?
    date("now", "%Y") == Time.now.year
  end
end

if StandardFilterCheck.new.date_supports_now?
  puts "NOTICE! 'now' is supported by 'date' filter. Remove the patch"
  sleep 5 # incur a penalty
else
  module Liquid::StandardFilters
    alias_method :date_orig, :date

    def date(input, format)
      input == "now" ? date_orig(Time.now, format) : date_orig(input, format)
    end
  end
end

module Serif
module Filters
  def strip(input)
    input.strip
  end

  def encode_uri_component(string)
    CGI.escape(string)
  end

  def markdown(body)
    Redcarpet::Markdown.new(Serif::MarkupRenderer, fenced_code_blocks: true).render(body).strip
  end

  def xmlschema(input)
    input.xmlschema
  end
end
end

Liquid::Template.register_filter(Serif::Filters)

module Serif
class Site
  def initialize(source_directory)
    @source_directory = source_directory
  end

  def directory
    @source_directory
  end

  # Returns all of the site's posts, in reverse chronological order
  # by creation time.
  def posts
    Post.all(self).sort_by { |entry| entry.created }.reverse
  end

  def drafts
    Draft.all(self)
  end

  def config
    Serif::Config.new(File.join(@source_directory, "_config.yml"))
  end

  def site_path(path)
    File.join("_site", path)
  end

  def tmp_path(path)
    File.join("tmp", site_path(path))
  end

  def latest_update_time
    most_recent = posts.max_by { |p| p.updated }
    most_recent ? most_recent.updated : Time.now
  end

  def bypass?(filename)
    !%w[.html .xml].include?(File.extname(filename))
  end

  # Returns the relative archive URL for the given date,
  # using the value of config.archive_url_format
  def archive_url_for_date(date)
    format = config.archive_url_format

    parts = {
      "year" => date.year.to_s,
      "month" => date.month.to_s.rjust(2, "0")
    }

    output = format

    parts.each do |placeholder, value|
      output = output.gsub(Regexp.quote(":" + placeholder), value)
    end

    output
  end

  # Returns a nested hash with the following structure:
  #
  # {
  #   :posts => [],
  #   :years => [
  #     {
  #       :date => Date.new(2012),
  #       :posts => [],
  #       :months => [
  #         { :date => Date.new(2012, 12), :archive_url => "/archive/2012/12", :posts => [] },
  #         { :date => Date.new(2012, 11), :archive_url => "/archive/2012/11", :posts => [] },
  #         # ...
  #       ]
  #     },
  #
  #     # ...
  #  ]
  # }
  def archives
    h = {}
    h[:posts] = posts

    # group posts by Date instances for the first day of the year
    year_groups = posts.group_by { |post| Date.new(post.created.year) }.to_a

    # collect all elements as maps for the year start date and the posts in that year
    year_groups.map! do |year_start_date, posts_by_year|
      {
        :date => year_start_date,
        :posts => posts_by_year.sort_by { |post| post.created }
      }
    end

    year_groups.sort_by! { |year_hash| year_hash[:date] }
    year_groups.reverse!

    year_groups.each do |year_hash|
      year_posts = year_hash[:posts]

      # group the posts in the year by month
      month_groups = year_posts.group_by { |post| Date.new(post.created.year, post.created.month) }.to_a

      # collect the elements as maps for the month start date and the posts in that month
      month_groups.map! do |month_start_date, posts_by_month|
        {
          :date => month_start_date,
          :posts => posts_by_month.sort_by { |post| post.created },
          :archive_url => archive_url_for_date(month_start_date)
        }
      end

      month_groups.sort_by! { |month_hash| month_hash[:date] }
      month_groups.reverse!

      # set the months for the current year
      year_hash[:months] = month_groups
    end

    h[:years] = year_groups

    # return the final hash
    h
  end

  def to_liquid
    {
      "posts" => posts,
      "latest_update_time" => latest_update_time,
      "archive" => self.class.stringify_keys(archives)
    }
  end

  def generate
    FileUtils.cd(@source_directory)

    FileUtils.rm_rf("tmp/_site")
    FileUtils.mkdir_p("tmp/_site")

    files = Dir["**/*"].select { |f| f !~ /\A_/ && File.file?(f) }

    default_layout = Liquid::Template.parse(File.read("_layouts/default.html"))

    # preprocess any drafts marked for autopublish, before grabbing the posts
    # to operate on.
    preprocess_autopublish_drafts

    posts = self.posts

    files.each do |path|
      puts "Processing file: #{path}"

      dirname = File.dirname(path)
      filename = File.basename(path)

      FileUtils.mkdir_p(tmp_path(dirname))
      if bypass?(filename)
        FileUtils.cp(path, tmp_path(path))
      else
        File.open(tmp_path(path), "w") do |f|
          file = File.read(path)
          title = nil
          layout_option = :default

          if Redhead::String.has_headers?(file)
            file_with_headers = Redhead::String[file]
            title = file_with_headers.headers[:title] && file_with_headers.headers[:title].value
            layout_option = file_with_headers.headers[:layout] && file_with_headers.headers[:layout].value
            layout_option ||= :default

            # all good? use the headered string
            file = file_with_headers
          end

          if layout_option == "none"
            f.puts Liquid::Template.parse(file.to_s).render!("site" => self)
          else
            layout_file = File.join(self.directory, "_layouts", "#{layout_option}.html")
            layout = Liquid::Template.parse(File.read(layout_file))
            f.puts layout.render!("page" => { "title" => [title].compact }, "content" => Liquid::Template.parse(file.to_s).render!("site" => self))
          end
        end
      end
    end

    posts.each do |post|
      puts "Processing post: #{post.path}"

      FileUtils.mkdir_p(tmp_path(File.dirname(post.url)))

      File.open(tmp_path(post.url + ".html"), "w") do |f|
        f.puts default_layout.render!("page" => { "title" => ["Posts", "#{post.title}"] }, "content" => Liquid::Template.parse(File.read("_templates/post.html")).render!("post" => post))
      end
    end

    generate_archives(default_layout)

    if Dir.exist?("_site")
      FileUtils.mv("_site", "/tmp/_site.#{Time.now.strftime("%Y-%m-%d-%H-%M-%S")}")
    end

    FileUtils.mv("tmp/_site", ".") && FileUtils.rm_rf("tmp/_site")
    FileUtils.rmdir("tmp")
  end

  private

  # goes through all draft posts that have "publish: now" headers and
  # calls #publish! on each one
  def preprocess_autopublish_drafts
    puts "Beginning pre-process step for drafts."
    drafts.each do |d|
      if d.autopublish?
        puts "Autopublishing draft: #{d.title} / #{d.slug}"
        d.publish!
      end
    end
  end

  # Uses config.archive_url_format to generate pages
  # using the archive_page.html template.
  def generate_archives(layout)
    return unless config.archive_enabled?

    template = Liquid::Template.parse(File.read("_templates/archive_page.html"))

    months = posts.group_by { |post| Date.new(post.created.year, post.created.month) }

    months.each do |month, posts|
      archive_path = tmp_path(archive_url_for_date(month))
      
      FileUtils.mkdir_p(archive_path)

      File.open(File.join(archive_path, "index.html"), "w") do |f|
        f.puts layout.render!("content" => template.render!("site" => self, "month" => month, "posts" => posts))
      end
    end
  end

  def self.stringify_keys(obj)
    return obj unless obj.is_a?(Hash) || obj.is_a?(Array)

    if obj.is_a?(Array)
      return obj.map do |el|
        stringify_keys(el)
      end
    end

    result = {}
    obj.each do |key, value|
      result[key.to_s] = stringify_keys(value)
    end
    result
  end
end
end