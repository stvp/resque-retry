require 'cgi'
require 'resque/server'
require 'resque/scheduler/server'

# Extend Resque::Server to add tabs.
module ResqueRetry
  module Server

    # Adds `resque-retry` web interface elements to `resque-web`
    #
    # @api private
    def self.included(base)
      base.class_eval {

        get '/retry' do
          erb local_template('retry.erb')
        end

        get '/retry/:timestamp' do
          erb local_template('retry_timestamp.erb')
        end

        post '/retry/:timestamp/remove' do
          Resque.delayed_timestamp_peek(params[:timestamp], 0, 0).each do |job|
            cancel_retry(job)
          end
          redirect u('retry')
        end

        post '/retry/:timestamp/jobs/:id/remove' do
          job = Resque.decode(params[:id])
          cancel_retry(job)
          redirect u("retry/#{params[:timestamp]}")
        end
      }
    end

    # Helper methods used by retry tab.
    module Helpers
      # builds a retry key for the specified job.
      #
      # This method was modified for the resque-web-public branch because we
      # don't have access to user code.
      def retry_key_for_job(job)
        # Adapted from Resque::Plugins::Retry#retry_identifier
        retry_identifier = Digest::SHA1.hexdigest( [job].join( '-' ) )

        # Adapted from Resque::Plugins::Retry#redis_retry_key
        ['resque-retry', job['class'], retry_identifier].compact.join(':').gsub(/\s/, '')
      end

      # gets the number of retry attempts for a job.
      def retry_attempts_for_job(job)
        Resque.redis.get(retry_key_for_job(job))
      end

      # gets the failure details hash for a job.
      def retry_failure_details(retry_key)
        Resque.decode(Resque.redis.get("failure-#{retry_key}"))
      end

      # reads a 'local' template file.
      def local_template(path)
        # Is there a better way to specify alternate template locations with sinatra?
        File.read(File.join(File.dirname(__FILE__), "server/views/#{path}"))
      end

      # cancels job retry
      #
      # This method was modified for the resque-web-public branch because we
      # don't have access to user code.
      def cancel_retry(job)
        retry_key = retry_key_for_job(job)
        Resque.remove_delayed(job['class'], *job['args'])
        Resque.redis.del("failure-#{retry_key}")
        Resque.redis.del(retry_key)
      end
    end

  end
end

Resque::Server.tabs << 'Retry'
Resque::Server.class_eval do
  include ResqueRetry::Server
  helpers ResqueRetry::Server::Helpers
end
