module StellarCoreCommander

  class LocalProcess < Process
    include Contracts

    attr_reader :pid
    attr_reader :wait

    def initialize(working_dir, base_port, identity, opts)
      stellar_core_bin = opts[:stellar_core_bin]
      if stellar_core_bin.blank?
        search = `which stellar-core`.strip

        if $?.success?
          stellar_core_bin = search
        else
          $stderr.puts "Could not find a `stellar-core` binary, please use --stellar-core-bin to specify"
          exit 1
        end
      end

      FileUtils.cp(stellar_core_bin, "#{working_dir}/stellar-core")
      super
    end

    Contract None => Any
    def forcescp
      run_cmd "./stellar-core", ["--forcescp"]
      raise "Could not set --forcescp" unless $?.success?
    end

    Contract None => Any
    def initialize_history
      run_cmd "./stellar-core", ["--newhist", "main"]
      raise "Could not initialize history" unless $?.success?
    end

    Contract None => Any
    def initialize_database
      run_cmd "./stellar-core", ["--newdb"]
      raise "Could not initialize db" unless $?.success?
    end

    Contract None => Any
    def create_database
      run_cmd "createdb", [database_name]
      raise "Could not create db: #{database_name}" unless $?.success?
    end

    Contract None => Any
    def drop_database
      run_cmd "dropdb", [database_name]
      raise "Could not drop db: #{database_name}" unless $?.success?
    end

    Contract None => Any
    def write_config
      IO.write("#{@working_dir}/stellar-core.cfg", config)
    end

    Contract None => Any
    def setup
      write_config
      create_database
      initialize_history
      initialize_database
    end

    Contract None => Num
    def run
      raise "already running!" if running?

      forcescp
      launch_stellar_core
    end


    Contract None => Bool
    def running?
      return false unless @pid
      ::Process.kill 0, @pid
      true
    rescue Errno::ESRCH
      false
    end

    Contract Bool => Bool
    def shutdown(graceful=true)
      return true if !running?

      if graceful
        ::Process.kill "INT", @pid
      else
        ::Process.kill "KILL", @pid
      end

      @wait.value.success?
    end

    Contract None => Any
    def cleanup
      database.disconnect
      shutdown
      drop_database
      rm_working_dir
    end

    Contract None => Any
    def dump_database
      Dir.chdir(@working_dir) do
        `pg_dump #{database_name} --clean --no-owner`
      end
    end


    Contract None => Sequel::Database
    def database
      @database ||= Sequel.postgres(database_name)
    end

    Contract None => String
    def database_name
      "stellar_core_tmp_#{basename}"
    end

    Contract None => String
    def dsn
      "postgresql://dbname=#{database_name}"
    end

    private
    def launch_stellar_core
      Dir.chdir @working_dir do
        sin, sout, serr, wait = Open3.popen3("./stellar-core")

        # throwaway stdout, stderr (the logs will record any output)
        Thread.new{ until (line = sout.gets).nil? ; end }
        Thread.new{ until (line = serr.gets).nil? ; end }

        @wait = wait
        @pid = wait.pid
      end
    end

    Contract None => String
    def config
      <<-EOS.strip_heredoc
        MANUAL_CLOSE=true
        PEER_PORT=#{peer_port}
        RUN_STANDALONE=false
        HTTP_PORT=#{http_port}
        PUBLIC_HTTP_PORT=false
        PEER_SEED="#{@identity.seed}"
        VALIDATION_SEED="#{@identity.seed}"
        QUORUM_THRESHOLD=1
        QUORUM_SET=["#{@identity.address}"]
        DATABASE="#{dsn}"

        [HISTORY.main]
        get="cp history/main/{0} {1}"
        put="cp {0} history/main/{1}"
        mkdir="mkdir -p history/main/{0}"
      EOS
    end

  end
end