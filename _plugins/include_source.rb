# frozen_string_literal: true
require "rouge"

module Jekyll
  class IncludeSourceTag < Liquid::Tag
    PREVIEW_EXTS = %w[.html .htm].freeze

    ASSETS = <<~HTML
      <style>
        .isrc { margin: 1rem 0 1.2rem; }
        .isrc-tabs { display: flex; gap: 0.5rem; margin-bottom: 0.5rem; }
        .isrc-tab {
          padding: 0.15rem 0.9rem;
          font-size: 0.85rem;
          line-height: 1.4;
          border-radius: 999px;
          border: 1px solid var(--language-border-color, #dee2e6);
          background: transparent;
          color: var(--code-header-text-color, inherit);
          cursor: pointer;
        }
        .isrc-tab:hover { border-color: var(--bs-primary, #3674b9); }
        .isrc-tab.isrc-active {
          background: var(--bs-primary, #3674b9);
          border-color: transparent;
          color: #fff;
        }
        .isrc-code .highlighter-rouge { margin-top: 0; margin-bottom: 0; }
        .isrc-preview {
          display: block;
          height: 480px;
          resize: vertical;
          overflow: hidden;
          background: #fff;
          border-radius: var(--bs-border-radius-lg, 0.75rem);
          box-shadow: var(--language-border-color, #dee2e6) 0 0 0 1px;
        }
        .isrc-preview iframe { display: block; width: 100%; height: 100%; border: 0; }
      </style>
      <script>
        (function () {
          document.addEventListener('click', function (e) {
            var btn = e.target.closest && e.target.closest('.isrc-tab');
            if (!btn) return;
            var box = btn.closest('.isrc');
            if (!box) return;
            var view = btn.getAttribute('data-view');
            var previewPane = box.querySelector('.isrc-preview');
            // 离开预览时把 iframe 重置回初始页，避免在预览里点链接跳走后回不来
            if (view === 'code' && previewPane && !previewPane.hidden) {
              box.querySelectorAll('.isrc-preview iframe').forEach(function (f) {
                f.src = f.getAttribute('data-src');
              });
            }
            box.querySelectorAll('.isrc-tab').forEach(function (t) {
              t.classList.toggle('isrc-active', t === btn);
            });
            box.querySelectorAll('.isrc-pane').forEach(function (p) {
              p.hidden = !p.classList.contains('isrc-' + view);
            });
          });
        })();
      </script>
    HTML

    def initialize(tag_name, markup, tokens)
      super
      args = markup.strip.split(/\s+/)
      @path = args.first.to_s
      @opts = args[1..] || []
    end

    def render(context)
      site = context.registers[:site]
      full_path = File.join(site.source, @path)
      return "<!-- include_source: #{@path} not found -->" unless File.exist?(full_path)

      content = File.read(full_path)
      content = content.sub(/\A---\s*\r?\n.*?\r?\n---\s*\r?\n/m, "").rstrip

      ext = File.extname(@path).downcase
      lexer = rouge_lexer(ext)
      table = Rouge::Formatters::HTMLTable.new(Rouge::Formatters::HTML.new).format(lexer.lex(content))
      basename = File.basename(@path)

      # 与 kramdown 输出一致，Chirpy 的 refactor-content 会自动补 code-header
      code = <<~HTML
        <div file="#{basename}" class="language-#{lexer.tag} highlighter-rouge"><div class="highlight"><code>#{table}</code></div></div>
      HTML

      previewable = PREVIEW_EXTS.include?(ext) && !@opts.include?("nopreview")
      return code unless previewable

      page = context.registers[:page] || {}
      inject_assets = page["_include_source_assets"].nil?
      page["_include_source_assets"] = true

      url = preview_url(site, full_path)
      default_preview = @opts.include?("preview")

      <<~HTML
        <div class="isrc">#{inject_assets ? ASSETS : ""}
          <div class="isrc-tabs">
            <button type="button" class="isrc-tab #{default_preview ? "" : "isrc-active"}" data-view="code">源码</button>
            <button type="button" class="isrc-tab #{default_preview ? "isrc-active" : ""}" data-view="preview">预览</button>
          </div>
          <div class="isrc-pane isrc-code"#{default_preview ? " hidden" : ""}>#{code}</div>
          <div class="isrc-pane isrc-preview"#{default_preview ? "" : " hidden"}><iframe src="#{url}" data-src="#{url}" loading="lazy" title="#{basename} 预览"></iframe></div>
        </div>
      HTML
    end

    private

    def rouge_lexer(ext)
      Rouge::Lexer.find(ext.delete_prefix(".")) ||
        begin
          Rouge::Lexer.guess_by_filename(File.basename(@path))
        rescue StandardError
          Rouge::Lexers::PlainText
        end
    end

    # 优先从 site.pages 取最终 URL（尊重文件 front matter 中的 permalink），
    # 取不到再按目录结构推导
    def preview_url(site, full_path)
      target = site.pages.find do |p|
        p.respond_to?(:path) && (p.path == @path || p.relative_path == @path)
      end
      url = target ? target_url(target) : derived_url
      "#{site.baseurl.to_s.chomp("/")}/#{url.sub(%r{\A/}, "")}"
    end

    # 目录式 permalink 下，只有 index.html 能被静态服务器当作目录索引；
    # 源文件是 .htm/.xhtml 时产物为 index.xxx，需要显式拼出文件名
    def target_url(target)
      url = target.url
      if url.end_with?("/")
        ext = File.extname(target.path).downcase
        url += "index#{ext}" unless ext == ".html"
      end
      url
    end

    def derived_url
      dir = File.dirname(@path)
      base = File.basename(@path)
      if base =~ /\Aindex\.(x?html?)\z/i
        "/#{dir}/"
      elsif base =~ /\.(x?html?)\z/i
        "/#{dir}/#{File.basename(base, File.extname(base))}/"
      else
        "/#{@path}"
      end
    end
  end
end

Liquid::Template.register_tag("include_source", Jekyll::IncludeSourceTag)
