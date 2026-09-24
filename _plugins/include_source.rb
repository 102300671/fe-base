# frozen_string_literal: true
require "rouge"
require "cgi"
require "uri"

module Jekyll
  # 从磁盘读取源文件，渲染为「源码 + 预览」双 tab 组件。
  # 与 `_includes/` 不同，被包含文件保留在原始位置，file:// 可直接打开。
  #
  # 用法：
  #   {% include_source labs/lab1/work1/index.html %}
  #   {% include_source labs/lab1/work1/index.html preview %}   默认显示预览
  #   {% include_source labs/lab1/work1/index.html nopreview %} 不显示 tab
  #   {% include_source labs/lab1/ dir %}                        遍历目录，包含其下全部文件
  #   {% include_source labs/lab1/ dir ext=html,css,js %}         仅包含指定后缀（逗号分隔，. 可省略）
  #   {% include_source labs/lab1/ dir recursive ext=html %}      递归遍历子目录
  #   {% include_source some/page.jsp base=https://host:port/ctx %}  标签内临时指定站外预览根地址
  #   {% include_source some/page.jsp fallback=http://host:port/ctx %} 标签内临时指定回退地址
  #   目录模式下 preview / nopreview 对其中每个文件分别生效
  #
  # _config.yml 可选配置（include_source 段）：
  #   preview_exts: [jsp, jspx]     追加可预览后缀（默认 html/htm/xhtml）
  #   preview_base: https://host/ctx  站外预览根地址
  #   preview_base_fallback: http://localhost:port/ctx  回退根地址（云端不可达时自动切换）
  #   webapp_root: src/main/webapp  映射到站外根地址的目录前缀
  #
  # 智能预览：只有「确实能打开」的文件才显示预览 tab ——
  #   站内文件需存在于构建输出（pages / static_files / documents），
  #   站外文件需位于 webapp_root 下（WEB-INF 等受保护目录除外）。
  class IncludeSourceTag < Liquid::Tag
    DEFAULT_PREVIEW_EXTS = %w[.html .htm .xhtml].freeze
    FRONT_MATTER  = /\A---\s*\r?\n.*?\r?\n---\s*\r?\n/m
    ASSETS_FLAG   = "_include_source_assets"
    ERR_PREFIX    = "include_source: "

    ASSETS = <<~HTML
      <style>
        .isrc { margin: 1rem 0 1.2rem; }
        .isrc-tabs { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.5rem; }
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
        .isrc-open {
          margin-left: auto;
          font-size: 0.8rem;
          text-decoration: none;
          color: var(--code-header-text-color, inherit);
          opacity: 0.75;
        }
        .isrc-open:hover { opacity: 1; text-decoration: underline; }
        .isrc-code .highlighter-rouge { margin-top: 0; margin-bottom: 0; }
        .isrc-preview {
          display: block;
          position: relative;
          height: 480px;
          resize: vertical;
          overflow: hidden;
          background: #fff;
          border-radius: var(--bs-border-radius-lg, 0.75rem);
          box-shadow: var(--language-border-color, #dee2e6) 0 0 0 1px;
        }
        .isrc-preview iframe { display: block; width: 100%; height: 100%; border: 0; }
        .isrc-notice {
          position: absolute; inset: 0;
          display: flex; align-items: center; justify-content: center;
          flex-direction: column; gap: 0.5rem;
          font-size: 0.9rem; color: #6c757d; background: #fff; text-align: center; padding: 1rem;
        }
        .isrc-notice a { color: var(--bs-primary, #3674b9); text-decoration: underline; }
      </style>
      <script>
        (function () {
          if (window.__isrc_bound) return;   /* 幂等：重复注入不重复绑定 */
          window.__isrc_bound = true;

          function setOpenLink(f, url) {
            var box = f.closest('.isrc');
            if (!box) return;
            var link = box.querySelector('.isrc-open');
            if (link) link.setAttribute('href', url);
          }

          /* 在预览区显示提示；sticky=true 时不允许重新探测（如 HTTP 混合内容永久阻断） */
          function showNotice(f, html, sticky) {
            f.src = 'about:blank';
            if (sticky) f.setAttribute('data-resolved', 'about:blank');
            var box = f.closest('.isrc');
            if (!box) return;
            var pane = box.querySelector('.isrc-preview');
            if (!pane) return;
            var old = pane.querySelector('.isrc-notice');
            if (old) old.remove();
            var div = document.createElement('div');
            div.className = 'isrc-notice';
            div.innerHTML = html;
            pane.appendChild(div);
          }

          /* 证书未信任时的提示 */
          function showCertNotice(f, url) {
            showNotice(f,
              '<p>需要先信任证书才能预览</p>' +
              '<p style="font-size:0.8rem">点击下方链接在新窗口打开，接受证书警告后回到此处再点「预览」</p>' +
              '<a href="' + url + '" target="_blank" rel="noopener">在新窗口打开 ↗</a>');
          }

          /* 主地址优先、回退兜底：fetch 探测主地址可达性，3s 超时则用 fallback */
          function resolveSrc(f) {
            var resolved = f.getAttribute('data-resolved');
            if (resolved) {
              if (resolved !== 'about:blank') { f.src = resolved; setOpenLink(f, resolved); }
              return;
            }
            var cloud = f.getAttribute('data-src');
            var local = f.getAttribute('data-fallback');
            if (!local || !cloud) { f.src = cloud || local || ''; return; }

            /* 清除可能存在的旧提示（证书信任后重新探测） */
            var box0 = f.closest('.isrc');
            if (box0) { var n0 = box0.querySelector('.isrc-notice'); if (n0) n0.remove(); }

            /* HTTPS 页面嵌入 HTTP 内容会被浏览器阻止（混合内容策略） */
            var httpsPage = location.protocol === 'https:';
            if (httpsPage && /^http:/.test(cloud)) {
              if (local && /^https:/.test(local)) {
                f.setAttribute('data-resolved', local);
                f.src = local; setOpenLink(f, local);
              } else {
                showNotice(f,
                  '<p>HTTPS 页面无法嵌入 HTTP 预览</p>' +
                  '<a href="' + cloud + '" target="_blank" rel="noopener">在新窗口打开 ↗</a>', true);
              }
              return;
            }

            /* HTTPS 页面 + HTTPS 主地址 + HTTP 回退 → 先探测证书是否已信任
               （自签证书未信任时 fetch 失败；信任后成功，iframe 可嵌入。
                不写 data-resolved，允许用户接受证书后重新点「预览」重试） */
            if (httpsPage && /^https:/.test(cloud) && /^http:/.test(local)) {
              var done2 = false;
              var ctrl2 = (typeof AbortController !== 'undefined') ? new AbortController() : null;
              var timer2 = setTimeout(function () {
                if (done2) return; done2 = true;
                if (ctrl2) try { ctrl2.abort(); } catch (e) {}
                showCertNotice(f, cloud);
              }, 3000);
              fetch(cloud, { mode: 'no-cors', cache: 'no-store',
                             signal: ctrl2 ? ctrl2.signal : undefined })
                .then(function () {
                  if (done2) return; done2 = true; clearTimeout(timer2);
                  f.setAttribute('data-resolved', cloud);
                  f.src = cloud; setOpenLink(f, cloud);
                })
                .catch(function () {
                  if (done2) return; done2 = true; clearTimeout(timer2);
                  showCertNotice(f, cloud);
                });
              return;
            }

            var done = false;
            var ctrl = (typeof AbortController !== 'undefined') ? new AbortController() : null;
            var timer = setTimeout(function () {
              if (done) return; done = true;
              if (ctrl) try { ctrl.abort(); } catch (e) {}
              f.setAttribute('data-resolved', local);
              f.src = local; setOpenLink(f, local);
            }, 3000);

            fetch(cloud, { mode: 'no-cors', cache: 'no-store',
                           signal: ctrl ? ctrl.signal : undefined })
              .then(function () {
                if (done) return; done = true; clearTimeout(timer);
                f.setAttribute('data-resolved', cloud);
                f.src = cloud; setOpenLink(f, cloud);
              })
              .catch(function () {
                if (done) return; done = true; clearTimeout(timer);
                f.setAttribute('data-resolved', local);
                f.src = local; setOpenLink(f, local);
              });
          }

          document.addEventListener('click', function (e) {
            var btn = e.target.closest && e.target.closest('.isrc-tab');
            if (!btn) return;
            var box = btn.closest('.isrc');
            if (!box) return;
            var view = btn.getAttribute('data-view');
            var previewPane = box.querySelector('.isrc-preview');

            /* 离开预览时把 iframe 重置回已解析地址，避免点链接跳走后回不来 */
            if (view === 'code' && previewPane && !previewPane.hidden) {
              box.querySelectorAll('.isrc-preview iframe').forEach(function (f) {
                var r = f.getAttribute('data-resolved');
                if (r) f.src = r;
              });
            }

            box.querySelectorAll('.isrc-tab').forEach(function (t) {
              var on = t === btn;
              t.classList.toggle('isrc-active', on);
              t.setAttribute('aria-selected', on ? 'true' : 'false');
            });
            box.querySelectorAll('.isrc-pane').forEach(function (p) {
              p.hidden = !p.classList.contains('isrc-' + view);
            });

            /* 切到预览时触发探测/加载 */
            if (view === 'preview') {
              var f = box.querySelector('.isrc-preview iframe');
              if (f && !f.getAttribute('data-resolved')) resolveSrc(f);
            }
          });

          /* 初始默认显示预览的组件立即探测 */
          function initShown() {
            document.querySelectorAll('.isrc-preview:not([hidden]) iframe')
              .forEach(function (f) {
                if (!f.getAttribute('data-resolved')) resolveSrc(f);
              });
          }
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', initShown);
          } else {
            initShown();
          }
        })();
      </script>
    HTML

    def initialize(tag_name, markup, tokens)
      super
      args  = markup.strip.split(/\s+/)
      @path = args.shift.to_s
      @opts = args.each_with_object({}) do |opt, h|
        k, v = opt.split("=", 2)
        h[k] = v || true
      end
    end

    def render(context)
      return err("missing path") if @path.empty?

      site = context.registers[:site]
      full = resolve(site)
      return err("not found: #{@path}") unless full

      if File.directory?(full)
        return err("is a directory: #{@path} (add 'dir' to traverse it)") unless directory_mode?
        render_directory(context, site, full)
      else
        render_file(context, site, full)
      end
    end

    def render_file(context, site, full, display_name: nil)
      stack = (Thread.current[:isrc_stack] ||= [])
      return err("circular: #{display_name || @path}") if stack.include?(full)

      stack.push(full)
      begin
        raw  = read_cached(site, full)
        code = render_code(strip_front_matter(raw), full, display_name)
        target = preview_target(site, full)
        return code unless previewable?(site, full, target)
        render_preview(context, site, code, full, target)
      rescue StandardError => e
        err("#{e.class}: #{e.message}")
      ensure
        stack.pop
      end
    end

    private

    # ---------- 路径 ----------

    def resolve(site)
      full = File.expand_path(@path, site.source)
      return nil unless full.start_with?(site.source)
      return nil unless File.file?(full) || File.directory?(full)
      full
    end

    # ---------- 目录遍历 ----------

    def directory_mode?
      @opts.key?("dir")
    end

    def render_directory(context, site, dir)
      files = collect_files(dir)
      return err("no matching files in: #{@path}") if files.empty?

      files.map do |f|
        rel = f.sub(/\A#{Regexp.escape(dir)}\/?/, "")
        render_file(context, site, f, display_name: rel)
      end.join("\n")
    end

    # 按相对路径排序，保证多次构建输出稳定；隐藏文件/目录（. 开头）始终排除
    def collect_files(dir)
      paths = if @opts.key?("recursive")
        Dir.glob(File.join(dir, "**", "*"))
      else
        Dir.children(dir).map { |name| File.join(dir, name) }
      end

      exts = allowed_extensions
      paths.select do |f|
        rel = f.sub(/\A#{Regexp.escape(dir)}\/?/, "")
        next false unless File.file?(f)
        next false if rel.split(File::SEPARATOR).any? { |seg| seg.start_with?(".") }
        next false if exts && !exts.include?(File.extname(f).downcase)
        true
      end.sort_by { |f| f.delete_prefix(dir) }
    end

    # ext=html,css,.js → [".html", ".css", ".js"]；缺省或为空表示不过滤
    def allowed_extensions
      raw = @opts["ext"]
      return nil if raw.nil? || raw.to_s.strip.empty?
      raw.to_s.split(",").map { |s| ".#{s.strip.delete_prefix(".").downcase}" }
         .reject { |ext| ext == "." }.uniq
    end

    # ---------- 读取（mtime + size 缓存）----------

    def read_cached(site, path)
      stat = File.stat(path)
      sig  = [stat.mtime.to_f, stat.size]

      cache = site.instance_variable_get(:@isrc_files) ||
              site.instance_variable_set(:@isrc_files, {})
      entry = cache[path]
      return entry[:content] if entry && entry[:sig] == sig

      content = File.read(path, encoding: "UTF-8")
      cache[path] = { sig: sig, content: content }
      content
    end

    def strip_front_matter(content)
      content.sub(FRONT_MATTER, "").rstrip
    end

    # ---------- 高亮 ----------

    def render_code(content, path, display_name = nil)
      ext   = File.extname(path).downcase
      lexer = find_lexer(ext, path, content)

      formatter = Rouge::Formatters::HTMLTable.new(
        Rouge::Formatters::HTML.new,
        table_class:  "rouge-table",
        gutter_class: "rouge-gutter gl",
        code_class:   "rouge-code"
      )
      table = formatter.format(lexer.lex(content))
      name  = CGI.escapeHTML(display_name || File.basename(path))

      # 结构与 kramdown + rouge 的默认输出一致：
      # <div class="language-x highlighter-rouge">
      #   <div class="highlight">
      #     <pre class="highlight"><code><table class="rouge-table">...</table></code></pre>
      #   </div>
      # </div>
      %(<div file="#{name}" class="language-#{lexer.tag} highlighter-rouge">) +
        %(<div class="highlight"><pre class="highlight"><code>#{table}</code></pre></div>) +
        %(</div>)
    end

    def find_lexer(ext, path, content)
      Rouge::Lexer.find(ext.delete_prefix(".")) ||
        guess_lexer(path) ||
        Rouge::Lexer.find_fancy("html", content) ||
        Rouge::Lexers::PlainText
    end

    def guess_lexer(path)
      result = Rouge::Lexer.guess_by_filename(File.basename(path))
      result.is_a?(Array) ? result.first : result
    rescue StandardError
      nil
    end

    # ---------- 预览 ----------

    # 可预览后缀：默认 html 系 + _config.yml 的 preview_exts 追加
    def preview_extensions(site)
      extra = Array(isrc_config(site)["preview_exts"]).flat_map do |s|
        s.to_s.split(",")
      end.map { |s| ".#{s.strip.delete_prefix(".").downcase}" }
         .reject { |ext| ext == "." }
      (DEFAULT_PREVIEW_EXTS + extra).uniq
    end

    # 只有后缀可预览、未显式 nopreview、且确实存在可打开的预览目标时才出 tab
    def previewable?(site, full, target = nil)
      return false if @opts.key?("nopreview")
      return false unless preview_extensions(site).include?(File.extname(full).downcase)
      !!(target || preview_target(site, full))
    end

    def render_preview(context, site, code, full, target)
      assets    = assets_for(context)
      raw_url, external = target
      url       = CGI.escapeHTML(raw_url)
      name      = CGI.escapeHTML(File.basename(full))
      pv_first  = @opts.key?("preview")

      # 站外预览且配置了回退地址 → iframe 初始留空，JS 探测主地址后加载
      fallback   = external ? preview_fallback_url(site, full) : nil
      has_fb     = external && !fallback.nil?
      iframe_src = has_fb ? "about:blank" : url
      fb_attr    = has_fb ? %( data-fallback="#{CGI.escapeHTML(fallback)}") : ""

      code_sel = pv_first ? "false" : "true"
      pv_sel   = pv_first ? "true"  : "false"
      code_cls = pv_first ? ""      : "isrc-active"
      pv_cls   = pv_first ? "isrc-active" : ""
      code_hid = pv_first ? " hidden" : ""
      pv_hid   = pv_first ? "" : " hidden"

      open_link = if external
        %(<a class="isrc-open" href="#{url}" target="_blank" rel="noopener">新窗口打开 ↗</a>)
      else
        ""
      end

      <<~HTML
        <div class="isrc">#{assets}
          <div class="isrc-tabs" role="tablist">
            <button type="button" role="tab" aria-selected="#{code_sel}"
                    class="isrc-tab #{code_cls}" data-view="code">源码</button>
            <button type="button" role="tab" aria-selected="#{pv_sel}"
                    class="isrc-tab #{pv_cls}" data-view="preview">预览</button>
            #{open_link}
          </div>
          <div class="isrc-pane isrc-code" role="tabpanel"#{code_hid}>#{code}</div>
          <div class="isrc-pane isrc-preview" role="tabpanel"#{pv_hid}>
            <iframe src="#{iframe_src}" data-src="#{url}"#{fb_attr} loading="lazy"
                    sandbox="allow-scripts allow-same-origin allow-forms allow-popups"
                    title="#{name} 预览"></iframe>
          </div>
        </div>
      HTML
    end

    # 同一 page 只注入一次 ASSETS；写入失败则退化为每次注入（JS 幂等守护）
    def assets_for(context)
      page = context.registers[:page]
      return ASSETS if page.nil?

      already = begin
        page[ASSETS_FLAG]
      rescue StandardError
        nil
      end
      return "" if already

      begin
        page[ASSETS_FLAG] = true
      rescue StandardError
        # 不支持写入就退化为每次注入
      end
      ASSETS
    end

    # ---------- URL 推导 ----------

    # 预览目标 [url, external?]；不存在可打开目标时返回 nil
    # 1) 文件位于 webapp_root 下且配置了站外根地址 → 站外 URL；
    # 2) 否则文件必须在构建输出中（pages / static_files / documents，尊重 permalink）。
    def preview_target(site, full)
      rel      = full.sub(/\A#{Regexp.escape(site.source)}\/?/, "")

      external = external_preview_url(site, rel)
      return [external, true] if external

      entry = output_index(site)[rel]
      return nil unless entry

      path = entry.respond_to?(:url) ? entry.url.to_s : "/#{rel}"
      path = encode_url(path) unless path.ascii_only?
      ["#{site.baseurl.to_s.chomp("/")}/#{path.sub(%r{\A/}, "")}", false]
    end

    # src/main/webapp/foo/bar.jsp（webapp_root=src/main/webapp）
    #   → http://host:port/ctx/foo/bar.jsp
    # 未配置 preview_base、文件不在 webapp_root 下、或位于 WEB-INF 受保护目录时返回 nil
    def external_preview_url(site, rel)
      base = preview_base(site)
      return nil unless base =~ %r{\Ahttps?://}

      mapped = mapped_relative(site, rel)
      return nil unless mapped
      return nil if mapped.split("/").first.to_s.downcase == "web-inf"
      "#{base}/#{encode_url(mapped)}"
    end

    # 文件相对站点根的路径 → 相对外部应用根的路径；不在 webapp_root 下返回 nil
    def mapped_relative(site, path_or_rel)
      root = webapp_root(site)
      return nil if root.empty?
      rel  = path_or_rel
      if File.absolute_path(rel).start_with?(site.source)
        rel = rel.sub(/\A#{Regexp.escape(site.source)}\/?/, "")
      end
      return nil unless rel.start_with?("#{root}/") || rel == root
      rel.sub(%r{\A#{Regexp.escape(root)}/?}, "")
    end

    # 标签参数 base= 优先，其次 _config.yml: include_source.preview_base
    def preview_base(site)
      raw = @opts["base"] || isrc_config(site)["preview_base"]
      raw.to_s.strip.sub(%r{/+\z}, "")
    end

    # 标签参数 fallback= 优先，其次 _config.yml: include_source.preview_base_fallback
    def preview_base_fallback(site)
      raw = @opts["fallback"] || isrc_config(site)["preview_base_fallback"]
      raw.to_s.strip.sub(%r{/+\z}, "")
    end

    # 回退预览 URL：与 external_preview_url 同构，用 preview_base_fallback
    def preview_fallback_url(site, full)
      base = preview_base_fallback(site)
      return nil unless base =~ %r{\Ahttps?://}

      rel    = full.sub(/\A#{Regexp.escape(site.source)}\/?/, "")
      mapped = mapped_relative(site, rel)
      return nil unless mapped
      return nil if mapped.split("/").first.to_s.downcase == "web-inf"
      "#{base}/#{encode_url(mapped)}"
    end

    # _config.yml: include_source.webapp_root（相对站点根，不带首尾 /）
    def webapp_root(site)
      isrc_config(site)["webapp_root"].to_s.strip.delete_prefix("/").sub(%r{/+\z}, "")
    end

    def isrc_config(site)
      cfg = site.config["include_source"]
      cfg.is_a?(Hash) ? cfg : {}
    end

    # 构建输出建一次索引（pages / static_files / documents），避免每次线性查找
    def output_index(site)
      cached = site.instance_variable_get(:@isrc_outputs)
      return cached if cached

      idx = {}
      entries = []
      entries.concat(site.pages)       if site.respond_to?(:pages)
      entries.concat(site.static_files) if site.respond_to?(:static_files)
      entries.concat(site.documents)   if site.respond_to?(:documents)

      entries.each do |p|
        if p.respond_to?(:relative_path) && p.relative_path
          key = p.relative_path.sub(%r{\A/}, "")
          idx[key] = p unless key.empty?
        end
        next unless p.respond_to?(:path) && p.path
        path = p.path
        if File.absolute_path(path) && path.start_with?(site.source)
          path = path.sub(/\A#{Regexp.escape(site.source)}\/?/, "")
        end
        key = path.sub(%r{\A/}, "")
        idx[key] = p unless key.empty?
      end

      site.instance_variable_set(:@isrc_outputs, idx)
      idx
    end

    def encode_url(url)
      url.split("/").map { |s| URI.encode_www_form_component(s).gsub("+", "%20") }.join("/")
    end

    # ---------- 错误输出 ----------

    def err(msg)
      "<!-- #{ERR_PREFIX}#{CGI.escapeHTML(msg)} -->"
    end
  end
end

Liquid::Template.register_tag("include_source", Jekyll::IncludeSourceTag)
