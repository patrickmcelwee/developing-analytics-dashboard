#
# Put your custom functions in this class in order to keep the files under lib untainted
#
# This class has access to all of the private variables in deploy/lib/server_config.rb
#
# any public method you create here can be called from the command line. See
# the examples below for more information.
#
class ServerConfig

  def deploy_data
    # deploy_patient_claims
    # deploy_insurance_claims
    deploy_northwind
  end

  def deploy_northwind
    log_header "Deploying Northwind raw data"
    clean_collections(['northwind-raw'])
    arguments = %W{
      import -input_file_path data/northwind/raw
      -input_compressed
      -output_uri_replace "#{ServerConfig.expand_path("#{@@path}/../data")},'',.zip,''"
      -output_collections northwind,northwind-raw
    }
    ruby_flavored_mlcp(arguments)

    log_header "Deploying Northwind employees"
    clean_collections(['northwind-employees'])
    arguments = %W{
      import -input_file_path data/northwind/employees
      -input_compressed
      -output_uri_replace "#{ServerConfig.expand_path("#{@@path}/../data")},'',.zip,''"
      -output_collections northwind,northwind-employees
    }
    ruby_flavored_mlcp(arguments)

    log_header "Deploying Northwind order details"
    clean_collections(['northwind-order-details'])
    arguments = %W{
      import -input_file_path data/northwind/order-details
      -input_compressed
      -output_uri_replace "#{ServerConfig.expand_path("#{@@path}/../data")},'',.zip,''"
      -output_collections northwind,northwind-order-details
      -transform_module /transform/northwind-order-details.xqy
      -transform_namespace http://marklogic.com/analytics-dashboard/northwind
    }
    ruby_flavored_mlcp(arguments)

    log_header "Deploying Northwind orders, harmonized"
    clean_collections(['northwind-orders'])
    arguments = %W{
      import -input_file_path data/northwind/orders
      -input_compressed
      -output_uri_replace "#{ServerConfig.expand_path("#{@@path}/../data")},'',.zip,''"
      -output_collections northwind,northwind-orders
      -transform_module /transform/northwind-orders.xqy
      -transform_namespace http://marklogic.com/analytics-dashboard/northwind
    }
    ruby_flavored_mlcp(arguments)
  end

  def deploy_insurance_claims
    log_header "Deploying DMLC Insurance Claims"
    clean_collections(['insurance-claims'])
    arguments = %W{
      import -input_file_path data/dmlc-insurance/claims
      -input_compressed
      -output_uri_replace "#{ServerConfig.expand_path("#{@@path}/../data")},'',.zip,''"
      -output_collections insurance-claims
    }
    ruby_flavored_mlcp(arguments)
  end

  def deploy_patient_claims
    log_header "Deploying Patient XML"
    arguments = %W{
      import -input_file_path data/claims-small/summary
      -input_file_type delimited_text
      -delimited_root_name patient-summary
      -output_uri_prefix /patients/
      -output_uri_suffix .xml
      -output_collections patient
    }
    ruby_flavored_mlcp(arguments)
  end

  def log_header(txt)
    logger.info(%Q{########################\n# #{txt}\n########################})
  end

  def ruby_flavored_mlcp(arguments)
    arguments.concat(role_permissions)
    arguments.each do |arg|
      ARGV.push(arg)
    end
    mlcp
  end

  def role_permissions
    role = @properties['ml.app-name'] + "-role"
    %W{ -output_permissions
        #{role},read,#{role},update,#{role},insert,#{role},execute}
  end

  #
  # You can easily "override" existing methods with your own implementations.
  # In ruby this is called monkey patching
  #
  # first you would rename the original method
  # alias_method :original_deploy_modules, :deploy_modules

  # then you would define your new method
  # def deploy_modules
  #   # do your stuff here
  #   # ...

  #   # you can optionally call the original
  #   original_deploy_modules
  # end

  #
  # you can define your own methods and call them from the command line
  # just like other roxy commands
  # ml local my_custom_method
  #
  # def my_custom_method()
  #   # since we are monkey patching we have access to the private methods
  #   # in ServerConfig
  #   @logger.info(@properties["ml.content-db"])
  # end

  #
  # to create a method that doesn't require an environment (local, prod, etc)
  # you woudl define a class method
  # ml my_static_method
  #
  # def self.my_static_method()
  #   # This method is static and thus cannot access private variables
  #   # but it can be called without an environment
  # end

  # Show-casing some useful overrides, as well as adjusting some module doc permissions
  alias_method :original_deploy_modules, :deploy_modules
  alias_method :original_deploy_rest, :deploy_rest
  alias_method :original_deploy, :deploy
  alias_method :original_clean, :clean

  # Integrate deploy_packages into the Roxy deploy command
  def deploy
    what = ARGV.shift

    case what
      when 'packages'
        deploy_packages
      else
        ARGV.unshift what
        original_deploy
    end
  end

  def deploy_modules
    # Uncomment deploy_packages if you would like to use MLPM to deploy MLPM packages, and
    # include MLPM deploy in deploy modules to make sure MLPM depencencies are loaded first.

    # Note: you can also move mlpm.json into src/ext/ and deploy plain modules (not REST extensions) that way.

    deploy_packages
    original_deploy_modules
  end
  
  def deploy_packages
    password_prompt
    system %Q!mlpm deploy -u #{ @ml_username } \
                          -p #{ @ml_password } \
                          -H #{ @properties['ml.server'] } \
                          -P #{ @properties['ml.app-port'] }!
    change_permissions(@properties["ml.modules-db"])
  end
  
  def deploy_rest
    original_deploy_rest
    change_permissions(@properties["ml.modules-db"])
  end

  # Permissions need to be changed for executable code that was not deployed via Roxy directly,
  # to make sure users with app-role can read and execute it. Typically applies to artifacts
  # installed via REST api, which only applies permissions for rest roles. Effectively also includes
  # MLPM, which uses REST api for deployment. It often also applies to artifacts installed with
  # custom code (via app_specific for instance), like alerts.
  def change_permissions(where)
    logger.info "Changing permissions in #{where} for:"
    r = execute_query(
      %Q{
        xquery version "1.0-ml";

        let $new-permissions := (
          xdmp:permission("#{@properties["ml.app-name"]}-role", "read"),
          xdmp:permission("#{@properties["ml.app-name"]}-role", "update"),
          xdmp:permission("#{@properties["ml.app-name"]}-role", "execute")
        )

        let $uris :=
          if (fn:contains(xdmp:database-name(xdmp:database()), "content")) then

            (: This is to make sure all alert files are accessible :)
            cts:uri-match("*alert*")

          else

            (: This is to make sure all triggers, schemas, modules and REST extensions are accessible :)
            cts:uris()

        let $fixes := 
          for $uri in $uris
          let $existing-permissions := xdmp:document-get-permissions($uri)
        
          (: Only apply new permissions if really necessary (gives better logging too):)
          where not(ends-with($uri, "/"))
            and count($existing-permissions[fn:string(.) = $new-permissions/fn:string(.)]) ne 3
        
          return (
            "  " || $uri,
            xdmp:document-set-permissions($uri, $new-permissions)
          )
        return
          if ($fixes) then
            $fixes
          else
            "  no changes needed.."
      },
      { :db_name => where }
    )
    r.body = parse_json r.body
    logger.info r.body
    logger.info ""
  end

  # Integrate clean_collections into the Roxy clean command
  def clean
    what = ARGV.shift

    case what
      when 'collections'
        clean_collections
      else
        ARGV.unshift what
        original_clean
    end
  end

  def clean_collections(collections)
    collections.each do |collection|
      r = execute_query(
        %Q{
          xquery version "1.0-ml";

          for $collection in fn:tokenize("#{collection}", ",")
          where fn:exists(fn:collection($collection)[1])
          return (
            xdmp:collection-delete($collection),
            "Cleaned collection " || $collection
          )
        },
        { :db_name => @properties["ml.content-db"]}
      )
      r.body = parse_body r.body
      logger.info r.body
    end
  end

end

#
# Uncomment, and adjust below code to get help about your app_specific
# commands included into Roxy help. (ml -h)
#

class Help
#  def self.app_specific
#    <<-DOC.strip_heredoc
#
#      App-specific commands:
#        example       Installs app-specific alerting
#    DOC
#  end
#
#  def self.example
#    <<-DOC.strip_heredoc
#      Usage: ml {env} example [args] [options]
#      
#      Runs a special example task against given environment.
#      
#      Arguments:
#        this    Do this
#        that    Do that
#        
#      Options:
#        --whatever=value
#    DOC
#  end
  class <<self
    alias_method :original_deploy, :deploy

    def deploy
      # Concatenate extra lines of documentation after original deploy
      # Help message (with a bit of indent to make it look better)
      original_deploy + "  " +
      <<-DOC.strip_heredoc
        packages    # deploys MLPM modules and REST extensions using MLPM to the app-port
      DOC
    end
    alias_method :original_clean, :clean

    def clean
      # Concatenate extra lines of documentation after original clean
      # Help message (with a bit of indent to make it look better)
      original_clean + "\n  " +
      <<-DOC.strip_heredoc
        collections WHAT
            # removes all files from (comma-separated list of) WHAT collection(s) in the content database
      DOC
    end
  end
end
