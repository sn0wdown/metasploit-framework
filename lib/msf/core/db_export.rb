# -*- coding: binary -*-
module Msf

##
#
# This class provides export capabilities
#
##
class DBManager
class Export

  attr_accessor :workspace

  def initialize(workspace)
    self.workspace = workspace
  end

  def myworkspace
    self.workspace
  end

  def myusername
    @username ||= (ENV['LOGNAME'] || ENV['USERNAME'] || ENV['USER'] || "unknown").to_s.strip.gsub(/[^A-Za-z0-9\x20]/n,"_")
  end

  # Hosts are always allowed. This is really just a stub.
  def host_allowed?(arg)
    true
  end


  # Performs an export of the workspace's `Metasploit::Credential::Login` objects in pwdump format
  # @param path [String] the path on the local filesystem where the exported data will be written
  # @return [void]
  def to_pwdump_file(path, &block)
    exporter = Metasploit::Credential::Exporter::Pwdump.new(workspace: workspace)

    File.open(path, 'w') do |file|
      file << exporter.rendered_output
    end
    true
  end


  def to_xml_file(path, &block)

    yield(:status, "start", "report") if block_given?
    extract_target_entries
    report_file = ::File.open(path, "wb")

    report_file.write %Q|<?xml version="1.0" encoding="UTF-8"?>\n|
    report_file.write %Q|<MetasploitV4>\n|
    report_file.write %Q|<generated time="#{Time.now.utc}" user="#{myusername}" project="#{myworkspace.name.gsub(/[^A-Za-z0-9\x20]/n,"_")}" product="framework"/>\n|

    yield(:status, "start", "hosts") if block_given?
    report_file.write %Q|<hosts>\n|
    report_file.flush
    extract_host_info(report_file)
    report_file.write %Q|</hosts>\n|

    yield(:status, "start", "events") if block_given?
    report_file.write %Q|<events>\n|
    report_file.flush
    extract_event_info(report_file)
    report_file.write %Q|</events>\n|

    yield(:status, "start", "services") if block_given?
    report_file.write %Q|<services>\n|
    report_file.flush
    extract_service_info(report_file)
    report_file.write %Q|</services>\n|

    yield(:status, "start", "credentials") if block_given?
    report_file.write %Q|<credentials>\n|
    report_file.flush
    extract_credential_info(report_file)
    report_file.write %Q|</credentials>\n|

    yield(:status, "start", "web sites") if block_given?
    report_file.write %Q|<web_sites>\n|
    report_file.flush
    extract_web_site_info(report_file)
    report_file.write %Q|</web_sites>\n|

    yield(:status, "start", "web pages") if block_given?
    report_file.write %Q|<web_pages>\n|
    report_file.flush
    extract_web_page_info(report_file)
    report_file.write %Q|</web_pages>\n|

    yield(:status, "start", "web forms") if block_given?
    report_file.write %Q|<web_forms>\n|
    report_file.flush
    extract_web_form_info(report_file)
    report_file.write %Q|</web_forms>\n|

    yield(:status, "start", "web vulns") if block_given?
    report_file.write %Q|<web_vulns>\n|
    report_file.flush
    extract_web_vuln_info(report_file)
    report_file.write %Q|</web_vulns>\n|

    yield(:status, "start", "module details") if block_given?
    report_file.write %Q|<module_details>\n|
    report_file.flush
    extract_module_detail_info(report_file)
    report_file.write %Q|</module_details>\n|


    report_file.write %Q|</MetasploitV4>\n|
    report_file.flush
    report_file.close

    yield(:status, "complete", "report") if block_given?

    true
  end

  # A convenience function that bundles together host, event, and service extraction.
  def extract_target_entries
    extract_host_entries
    extract_event_entries
    extract_service_entries
    extract_credential_entries
    extract_note_entries
    extract_vuln_entries
    extract_web_entries
  end

  # Extracts all the hosts from a project, storing them in @hosts and @owned_hosts
  def extract_host_entries
    @owned_hosts = []
    @hosts = myworkspace.hosts
    @hosts.each do |host|
      if host.notes.find :first, :conditions => { :ntype => 'pro.system.compromise' }
        @owned_hosts << host
      end
    end
  end

  # Extracts all events from a project, storing them in @events
  def extract_event_entries
    @events = myworkspace.events.find :all, :order => 'created_at ASC'
  end

  # Extracts all services from a project, storing them in @services
  def extract_service_entries
    @services = myworkspace.services
  end

  # Extracts all credentials from a project, storing them in @creds
  def extract_credential_entries
    @creds = Metasploit::Credential::Core.with_logins.with_public.with_private.workspace_id(myworkspace.id)
  end

  # Extracts all notes from a project, storing them in @notes
  def extract_note_entries
    @notes = myworkspace.notes
  end

  # Extracts all vulns from a project, storing them in @vulns
  def extract_vuln_entries
    @vulns = myworkspace.vulns
  end

  # Extract all web entries, storing them in instance variables
  def extract_web_entries
    @web_sites = myworkspace.web_sites
    @web_pages = myworkspace.web_pages
    @web_forms = myworkspace.web_forms
    @web_vulns = myworkspace.web_vulns
  end

  # Simple marshalling, for now. Can I use ActiveRecord::ConnectionAdapters::Quoting#quote
  # directly? Is it better to just marshal everything and destroy readability? Howabout
  # XML safety?
  def marshalize(obj)
    case obj
    when String
      obj.strip
    when TrueClass, FalseClass, Float, Fixnum, Bignum, Time
      obj.to_s.strip
    when BigDecimal
      obj.to_s("F")
    when NilClass
      "NULL"
    else
      [Marshal.dump(obj)].pack("m").gsub(/\s+/,"")
    end
  end

  def create_xml_element(key,value,skip_encoding=false)
    tag = key.gsub("_","-")
    el = REXML::Element.new(tag)
    if value
      unless skip_encoding
        data = marshalize(value)
        data.force_encoding(Encoding::BINARY) if data.respond_to?('force_encoding')
        data.gsub!(/([\x00-\x08\x0b\x0c\x0e-\x1f\x80-\xFF])/n){ |x| "\\x%.2x" % x.unpack("C*")[0] }
        el << REXML::Text.new(data)
      else
        el << value
      end
    end
    return el
  end

  # @note there is no single root element output by
  #   {#extract_module_detail_info}, so if calling {#extract_module_detail_info}
  #   directly, it is the caller's responsibility to add an opening and closing
  #   tag to report_file around the call to {#extract_module_detail_info}.
  #
  # Writes a module_detail element to the report_file for each
  # Mdm::Module::Detail.
  #
  # @param report_file [#write, #flush] IO stream to which to write the
  #   module_detail elements.
  # @return [void]
  def extract_module_detail_info(report_file)
      Mdm::Module::Detail.all.each do |m|
      report_file.write("<module_detail>\n")
      #m_id = m.attributes["id"]

      # Module attributes
      m.attributes.each_pair do |k,v|
        el = create_xml_element(k,v)
        report_file.write("    #{el}\n") # Not checking types
      end

      # Authors sub-elements
      # @todo https://www.pivotaltracker.com/story/show/48451001
      report_file.write("    <module_authors>\n")
      m.authors.find(:all).each do |d|
        d.attributes.each_pair do |k,v|
          el = create_xml_element(k,v)
          report_file.write("        #{el}\n")
        end
      end
      report_file.write("    </module_authors>\n")

      # Refs sub-elements
      # @todo https://www.pivotaltracker.com/story/show/48451001
      report_file.write("    <module_refs>\n")
      m.refs.find(:all).each do |d|
        d.attributes.each_pair do |k,v|
          el = create_xml_element(k,v)
          report_file.write("        #{el}\n")
        end
      end
      report_file.write("    </module_refs>\n")


      # Archs sub-elements
      # @todo https://www.pivotaltracker.com/story/show/48451001
      report_file.write("    <module_archs>\n")
      m.archs.find(:all).each do |d|
        d.attributes.each_pair do |k,v|
          el = create_xml_element(k,v)
          report_file.write("        #{el}\n")
        end
      end
      report_file.write("    </module_archs>\n")


      # Platforms sub-elements
      # @todo https://www.pivotaltracker.com/story/show/48451001
      report_file.write("    <module_platforms>\n")
      m.platforms.find(:all).each do |d|
        d.attributes.each_pair do |k,v|
          el = create_xml_element(k,v)
          report_file.write("        #{el}\n")
        end
      end
      report_file.write("    </module_platforms>\n")


      # Targets sub-elements
      # @todo https://www.pivotaltracker.com/story/show/48451001
      report_file.write("    <module_targets>\n")
      m.targets.find(:all).each do |d|
        d.attributes.each_pair do |k,v|
          el = create_xml_element(k,v)
          report_file.write("        #{el}\n")
        end
      end
      report_file.write("    </module_targets>\n")

      # Actions sub-elements
      # @todo https://www.pivotaltracker.com/story/show/48451001
      report_file.write("    <module_actions>\n")
      m.actions.find(:all).each do |d|
        d.attributes.each_pair do |k,v|
          el = create_xml_element(k,v)
          report_file.write("        #{el}\n")
        end
      end
      report_file.write("    </module_actions>\n")

      # Mixins sub-elements
      # @todo https://www.pivotaltracker.com/story/show/48451001
      report_file.write("    <module_mixins>\n")
      m.mixins.find(:all).each do |d|
        d.attributes.each_pair do |k,v|
          el = create_xml_element(k,v)
          report_file.write("        #{el}\n")
        end
      end
      report_file.write("    </module_mixins>\n")

      report_file.write("</module_detail>\n")
    end
    report_file.flush
  end

  # ActiveRecord's to_xml is easy and wrong. This isn't, on both counts.
  def extract_host_info(report_file)
    @hosts.each do |h|
      report_file.write("  <host>\n")
      host_id = h.attributes["id"]

      # Host attributes
      h.attributes.each_pair do |k,v|
        el = create_xml_element(k,v)
        report_file.write("    #{el}\n") # Not checking types
      end

      # Host details sub-elements
      report_file.write("    <host_details>\n")
      h.host_details.find(:all).each do |d|
        report_file.write("        <host_detail>\n")
        d.attributes.each_pair do |k,v|
          el = create_xml_element(k,v)
          report_file.write("            #{el}\n")
        end
        report_file.write("        </host_detail>\n")
      end
      report_file.write("    </host_details>\n")

      # Host exploit attempts sub-elements
      report_file.write("    <exploit_attempts>\n")
      h.exploit_attempts.find(:all).each do |d|
        report_file.write("        <exploit_attempt>\n")
        d.attributes.each_pair do |k,v|
          el = create_xml_element(k,v)
          report_file.write("            #{el}\n")
        end
        report_file.write("        </exploit_attempt>\n")
      end
      report_file.write("    </exploit_attempts>\n")

      # Service sub-elements
      report_file.write("    <services>\n")
      @services.find_all_by_host_id(host_id).each do |e|
        report_file.write("      <service>\n")
        e.attributes.each_pair do |k,v|
          el = create_xml_element(k,v)
          report_file.write("      #{el}\n")
        end
        report_file.write("      </service>\n")
      end
      report_file.write("    </services>\n")

      # Notes sub-elements
      report_file.write("    <notes>\n")
      @notes.find_all_by_host_id(host_id).each do |e|
        report_file.write("      <note>\n")
        e.attributes.each_pair do |k,v|
          el = create_xml_element(k,v)
          report_file.write("      #{el}\n")
        end
        report_file.write("      </note>\n")
      end
      report_file.write("    </notes>\n")

      # Vulns sub-elements
      report_file.write("    <vulns>\n")
      @vulns.find_all_by_host_id(host_id).each do |e|
        report_file.write("      <vuln>\n")
        e.attributes.each_pair do |k,v|
          el = create_xml_element(k,v)
          report_file.write("      #{el}\n")
        end

        # References
        report_file.write("        <refs>\n")
        e.refs.each do |ref|
          el = create_xml_element("ref",ref.name)
          report_file.write("          #{el}\n")
        end
        report_file.write("        </refs>\n")


        # Vuln details sub-elements
        report_file.write("            <vuln_details>\n")
        e.vuln_details.find(:all).each do |d|
          report_file.write("                <vuln_detail>\n")
          d.attributes.each_pair do |k,v|
            el = create_xml_element(k,v)
            report_file.write("                    #{el}\n")
          end
          report_file.write("                </vuln_detail>\n")
        end
        report_file.write("            </vuln_details>\n")


        # Vuln attempts sub-elements
        report_file.write("            <vuln_attempts>\n")
        e.vuln_attempts.find(:all).each do |d|
          report_file.write("                <vuln_attempt>\n")
          d.attributes.each_pair do |k,v|
            el = create_xml_element(k,v)
            report_file.write("                    #{el}\n")
          end
          report_file.write("                </vuln_attempt>\n")
        end
        report_file.write("            </vuln_attempts>\n")

        report_file.write("      </vuln>\n")
      end
      report_file.write("    </vulns>\n")

      report_file.write("  </host>\n")
    end
    report_file.flush
  end

  # Extract event data from @events
  def extract_event_info(report_file)
    @events.each do |e|
      report_file.write("  <event>\n")
      e.attributes.each_pair do |k,v|
        el = create_xml_element(k,v)
        report_file.write("      #{el}\n")
      end
      report_file.write("  </event>\n")
      report_file.write("\n")
    end
    report_file.flush
  end

  # Extract service data from @services
  def extract_service_info(report_file)
    @services.each do |e|
      report_file.write("  <service>\n")
      e.attributes.each_pair do |k,v|
        el = create_xml_element(k,v)
        report_file.write("      #{el}\n")
      end
      report_file.write("  </service>\n")
      report_file.write("\n")
    end
    report_file.flush
  end

  # Extract credential data from @creds
  def extract_credential_info(report_file)
    write_extracted_credential_cores(report_file)
    write_extracted_credential_origins(report_file)
    write_extracted_credential_realms(report_file)
    write_extracted_credential_publics(report_file)
    write_extracted_credential_logins(report_file)
    write_extracted_credential_privates(report_file)
  end

  # FSM, please make it stop
  # TODO: move this and everything else to use Nokogiri::Builder...
  def write_extracted_credential_cores(report_file)
    report_file.write("  <cores>\n")
    @creds.each do |core|
      report_file.write("<core>\n")
      core.attributes.each do |attr, val|
        element = create_xml_element(attr, val)
        report_file.write(    "#{element}\n")
      end
      report_file.write("</core>\n")
    end
    report_file.write("</cores>\n")
  end

  # FSM, please make it stop
  # TODO: move this and everything else to use Nokogiri::Builder...
  def write_extracted_credential_publics(report_file)
    report_file.write("  <publics>\n")
    @creds.each do |core|
      if core.public.present?
        report_file.write("<public>\n")
        core.public.attributes.each do |attr, val|
          element = create_xml_element(attr, val)
          report_file.write("#{element}\n")
        end
        report_file.write("</public>\n")
      end
    end
    report_file.write("</publics>\n")
  end

  # FSM, please make it stop
  # TODO: move this and everything else to use Nokogiri::Builder...
  def write_extracted_credential_privates(report_file)
    report_file.write("<privates>\n")
    @creds.each do |core|
      if core.private.present?
        report_file.write("<private>\n")
        core.private.attributes.each do |attr, val|
          if attr == 'data'
            val = REXML::CData.new(val)
            element = create_xml_element(attr, val, true)
          else
            element = create_xml_element(attr, val)
          end
          report_file.write("#{element}\n")
        end
        report_file.write("</private>\n")
      end
    end
    report_file.write("</privates>\n")
  end

  # FSM, please make it stop
  # TODO: move this and everything else to use Nokogiri::Builder...
  def write_extracted_credential_logins(report_file)
    report_file.write("  <logins>\n")
    @creds.each do |core|
      if core.logins.present?
        core.logins.each do |login|
          report_file.write("<login>\n")
          login.attributes.each do |attr, val|
            element = create_xml_element(attr, val)
            report_file.write("#{element}\n")
          end
          report_file.write("</login>\n")
        end
      end
    end
    report_file.write("</logins>\n")
  end

  # FSM, please make it stop
  # TODO: move this and everything else to use Nokogiri::Builder...
  def write_extracted_credential_origins(report_file)
    report_file.write("  <origins>\n")
    @creds.each do |core|
      report_file.write("<origin>\n")
      core.origin.attributes.each do |attr, val|
        element = create_xml_element(attr, val)
        report_file.write("#{element}\n")
      end
      report_file.write("</origin>\n")
    end
    report_file.write("</origins>\n")
  end

  # FSM, please make it stop
  # TODO: move this and everything else to use Nokogiri::Builder...
  def write_extracted_credential_realms(report_file)
    report_file.write("  <realms>\n")
    @creds.each do |core|
      if core.realm.present?
        report_file.write("<realm>\n")
        core.realm.attributes.each do |attr, val|
          element = create_xml_element(attr, val)
          report_file.write("#{element}\n")
        end
        report_file.write("</realm>\n")
      end
    end
    report_file.write("</realms>\n")
  end

  # Extract service data from @services
  def extract_service_info(report_file)
    @services.each do |e|
      report_file.write("  <service>\n")
      e.attributes.each_pair do |k,v|
        el = create_xml_element(k,v)
        report_file.write("      #{el}\n")
      end
      report_file.write("  </service>\n")
      report_file.write("\n")
    end
    report_file.flush
  end

  # Extract web site data from @web_sites
  def extract_web_site_info(report_file)
    @web_sites.each do |e|
      report_file.write("  <web_site>\n")
      e.attributes.each_pair do |k,v|
        el = create_xml_element(k,v)
        report_file.write("      #{el}\n")
      end

      site = e
      el = create_xml_element("host", site.service.host.address)
      report_file.write("      #{el}\n")

      el = create_xml_element("port", site.service.port)
      report_file.write("      #{el}\n")

      el = create_xml_element("ssl", site.service.name == "https")
      report_file.write("      #{el}\n")

      report_file.write("  </web_site>\n")
    end
    report_file.flush
  end

  # Extract web pages, forms, and vulns
  def extract_web_info(report_file, tag, entries)
    entries.each do |e|
      report_file.write("  <#{tag}>\n")
      e.attributes.each_pair do |k,v|
        el = create_xml_element(k,v)
        report_file.write("      #{el}\n")
      end

      site = e.web_site
      el = create_xml_element("vhost", site.vhost)
      report_file.write("      #{el}\n")

      el = create_xml_element("host", site.service.host.address)
      report_file.write("      #{el}\n")

      el = create_xml_element("port", site.service.port)
      report_file.write("      #{el}\n")

      el = create_xml_element("ssl", site.service.name == "https")
      report_file.write("      #{el}\n")

      report_file.write("  </#{tag}>\n")
    end
    report_file.flush
  end

  # Extract web pages
  def extract_web_page_info(report_file)
    extract_web_info(report_file, "web_page", @web_pages)
  end

  # Extract web forms
  def extract_web_form_info(report_file)
    extract_web_info(report_file, "web_form", @web_forms)
  end

  # Extract web vulns
  def extract_web_vuln_info(report_file)
    extract_web_info(report_file, "web_vuln", @web_vulns)
  end

end
end
end

