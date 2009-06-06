class GoogleSites
  def initialize(sites_path, notify=true, ua='Mac Safari')
    @sites_path = sites_path
    @uri = 'https://sites.google.com' + @sites_path
    @notify = notify
    @wuid, @rev, @jotxtok = nil, nil, nil
    @agent = WWW::Mechanize.new
    @agent.user_agent_alias = ua
    @system_path = {
      :gateway => "system/services/gateway?jot.xtok=",
      :create => "system/services/create?jot.xtok=",
      :delete => "system/services/delete?jot.xtok=",
      :editorSave => "system/services/editorSave?jot.xtok=",
      :lockNode => "system/services/lockNode?jot.xtok=",
      :loadRecentChanges => "/system/services/loadRecentChanges?jot.xtok=",
      :shallowSearch => "/system/services/shallowSearch?jot.xtok=",
      :createPage => "system/app/pages/createPage",
      :DefaultForm => "/system/app/forms/DefaultForm"
    }
  end

  def notify(&callback)
    callback.call if @notify == true
  end

  def login(email, passwd)
    login_page = @agent.get(@uri)
    login_form = login_page.forms.first

    login_form['Email'] = email
    login_form['Passwd'] = passwd
    @agent.submit(login_form)

    self.get
    self.set_jotxtok
  end

  def get(target_path='')
    uri = @uri + target_path

    begin
      @agent.get(uri)
    rescue => e
      self.notify { raise PageGetError, e }
    end
  end

  def set_jotxtok
    @jotxtok = @agent.cookie_jar.jar["sites.google.com"]["jotxtok"].value

    self.notify { raise JotxtokError, '[ERROR] jotxtok is blank.' } if @jotxtok.blank?
  end

  def set_wuid
    @agent.page.search("div.goog-menuitem").each do |wuid|
      if !wuid.nil? && /wuid:gx:([a-zA-Z0-9]+)/ =~ wuid.to_s
        @wuid = $1
        return
      end
    end

    self.notify { raise WuidError, '[ERROR] wuid is blank.' } if @wuid.blank?
  end

  def set_rev
    @agent.post_connect_hooks <<  Proc.new { |params|
      @rev = $1 if /revision\":(\d+)/ =~ params[:response_body]
    }
    page = @uri + @system_path[:lockNode] + @jotxtok
    @agent.post(page, "json" => "{\"wuid\" => \"wuid:gx:#{@wuid}\"}")
    @agent.post_connect_hooks.clear

    self.notify { raise RevError, '[ERROR] rev is blank.' } if @rev.blank?
  end

  def asciify(path)
    unless /^(?:-*[a-z0-9])+$/ =~ path
      page = @uri + @system_path[:gateway] + @jotxtok
      rst = @agent.post(page,"json" => "{\"string\":\"#{path}\",\"hasDelimiter\":true,\"service\":\"Asciify\"}")
      path = $1 if /:\"([a-z0-9-]+)\"/ =~ rst.body
    end
    path
  end

  def create(path_name, title, text='', source_path='')
    target_path = @system_path[:createPage] + "?source=/" + source_path
    self.get(target_path)

    path_name = self.asciify(path_name)
    source_path = source_path + '/' unless source_path.empty?
    path_name = source_path + path_name

    page = @uri + @system_path[:create] + @jotxtok
    pagetype = "text"
    requestPath = @sites_path + @system_path[:createPage]

    title.to_single_quote!.to_br!

    rst = @agent.post(page, "json" => "{
        \"path\":\"/#{path_name}\",
        \"pagetype\":\"#{pagetype}\",
        \"properties\":{
          \"main/title\":\"#{title}\"
        },
        \"requestPath\":\"#{requestPath}\"
      }"
    )

    if !rst.nil? && rst.body["error"].nil?
      self.notify { puts "[CREATE] TITLE:#{title}, PATH:#{path_name}" }
      self.edit(path_name, title, text) unless text.empty?
    else
      self.notify {
        e = rst.body.delete_space!
        raise PageCreateError, "[ERROR] create error. TITLE:#{title}, PATH:#{path_name}, MESSAGE:#{e}"
      }
    end
  end

  def edit(target_path, title, text)
    self.get(target_path)
    self.set_wuid
    self.set_rev

    page = @uri + @system_path[:editorSave] + @jotxtok
    requestPath = @sites_path + target_path

    title.to_single_quote!.to_br!
    text.to_single_quote!.to_br!

    rst = @agent.post(page,
      "json" => "{
        \"uri\":\"wuid:gx:#{@wuid}\",
        \"form\":\"#{@system_path[:DefaultForm]}\",
        \"properties\":{
          \"main/text\":[\"<DIV DIR='ltr'>#{text}</DIV>\"],
          \"main/title\":\"#{title}\"},
        \"requestPath\":\"#{requestPath}\",
        \"verifyLockRevision\":#{@rev}
      }"
    )

    if !rst.nil? && rst.body["error"].nil?
      self.notify { puts "[EDIT] TITLE:#{title}, PATH:#{requestPath}" }
    else
      self.notify {
        e = rst.body.delete_space!
        raise PageEditError, "[ERROR] edit error. TITLE:#{title}, PATH:#{requestPath}, MESSAGE:#{e}"
      }
    end
  end

  def delete(path_name)
    page = @uri + @system_path[:delete] + @jotxtok

    begin
      @agent.post(page,
        "json" => "{
          \"path\":\"/#{path_name}\",
          \"removeChildren\":true
        }"
      )
    rescue => e
      self.notify { raise PageDeleteError, e }
    else
      self.notify { puts "[DELETE] PATH:#{path_name}" }
    end
  end

  def move(path_name,new_path_name)
    page = @uri + @system_path[:gateway] + @jotxtok

    rst = @agent.post(page,
      "json" => "{
        \"path\":\"/#{path_name}\",
        \"newPath\":\"/#{new_path_name}\",
        \"service\":\"MoveNode\"
      }"
    )

    if !rst.nil? && rst.body["error"].nil?
      self.notify { puts "[MOVE] PATH:#{path_name}, NEWPATH:#{new_path_name}" }
    else
      self.notify {
        e = rst.body.delete_space!
        raise PageMoveError, "[ERROR] move error. PATH:#{path_name}, NEWPATH:#{new_path_name}, MESSAGE:#{e}"
      }
    end
  end

  def load_recent_changes(currentPath)
    page = @uri + @system_path[:loadRecentChanges] + @jotxtok
    rst = @agent.post(page,
      "json" => "{
        \"excludeCurrentPath\":true,
        \"currentPath\":\"/#{currentPath}\"
      }"
    )
    self.notify { puts "[LOAD RECENT CHANGES] #{rst.body}" }
  end

  def get_path(filter='')
    page = @uri + @system_path[:shallowSearch] + @jotxtok
    rst = @agent.post(page,
      "json" => "{
        \"forAll\":true," +
        #\"filter\":\"#{filter}\"
      "}"
    )
    self.notify { puts "[ALL PATH] #{rst.body}" }
  end
end

class Object
  def blank?
    if self.nil? || self.empty?
      return true
    end
    false
  end
end

class String
  def delete_space!
    self.gsub!(/\n/,'')
    self.gsub!(/([\s][\s])+/,'')
    self
  end

  def to_single_quote!
    self.gsub!(/"/,"'")
    self
  end

  def to_br!
    self.gsub!(/\r\n|\r|\n/, '<br />')
    self
  end
end

class JotxtokError < StandardError; end
class RevError < StandardError; end
class WuidError < StandardError; end
class PageGetError < StandardError; end
class PageCreateError < StandardError; end
class PageEditError < StandardError; end
class PageMoveError < StandardError; end
class PageDeleteError < StandardError; end