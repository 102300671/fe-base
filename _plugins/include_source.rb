# frozen_string_literal: true
module Jekyll
  class IncludeSourceTag < Liquid::Tag
    def initialize(tag_name, markup, tokens)
      super
      @path = markup.strip
    end

    def render(context)
      site = context.registers[:site]
      full_path = File.join(site.source, @path)

      unless File.exist?(full_path)
        return "<!-- include_source: #{@path} not found -->"
      end

      content = File.read(full_path)

      # 去掉 front matter
      content = content.sub(/\A---\s*\r?\n.*?\r?\n---\s*\r?\n/m, "")

      # 让被包含文件里的 Liquid 也生效（可选，去掉这一行就是纯静态包含）
      Liquid::Template.parse(content).render(context)
    end
  end
end

Liquid::Template.register_tag("include_source", Jekyll::IncludeSourceTag)