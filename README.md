resque-retry
============

A [Resque][resque] plugin. Requires Resque ~> 1.25 & [resque-scheduler][resque-scheduler] ~> 4.0.

This gem provides retry, delay and exponential backoff support for resque jobs.

  * Redis backed retry count/limit.
  * Retry on all or specific exceptions.
  * Exponential backoff (varying the delay between retrys).
  * Multiple failure backend with retry suppression & resque-web tab.
  * Small & Extendable - plenty of places to override retry logic/settings.

[![Build Status](https://secure.travis-ci.org/lantins/resque-retry.png?branch=master)](http://travis-ci.org/lantins/resque-retry)
[![Dependency Status](https://gemnasium.com/lantins/resque-retry.png)](https://gemnasium.com/lantins/resque-retry)

Install & Quick Start
---------------------

To install:
```
$ gem install resque-retry
```

If you're using [Bundler][bundler] to manage your dependencies, you should add
`gem 'resque-retry'` to your `Gemfile`.

Add this to your `Rakefile`:
```ruby
require 'resque/tasks'
require 'resque/scheduler/tasks'
```

The delay between retry attempts is provided by [resque-scheduler][resque-scheduler].
You'll want to run the scheduler process, otherwise delayed retry attempts
will never perform:
```
$ rake resque:scheduler
```

Use the plugin:
```ruby
require 'resque-retry'

class ExampleRetryJob
  extend Resque::Plugins::Retry
  @queue = :example_queue

  @retry_limit = 3
  @retry_delay = 60

  def self.perform(*args)
    # your magic/heavy lifting goes here.
  end
end
```

Then start up a resque worker as normal:
```
$ QUEUE=* rake resque:work
```

Now if you ExampleRetryJob fails, it will be retried 3 times, with a 60 second
delay between attempts.

For more explanation and examples, please see the remaining documentation.

Failure Backend & Resque Web Additions
--------------------------------------

Lets say you're using the Redis failure backend of resque (the default).
Every time a job fails, the failure queue is populated with the job and
exception details.

Normally this is useful, but if your jobs retry... it can cause a bit of a mess.

For example: given a job that retried 4 times before completing successful.
You'll have a lot of failures for the same job and you wont be sure if it
actually completed successfully just by just using the resque-web interface.

### Failure Backend

`MultipleWithRetrySuppression` is a multiple failure backend, with retry
suppression.

Here's an example, using the Redis failure backend:
```ruby
require 'resque-retry'
require 'resque/failure/redis'

# require your jobs & application code.

Resque::Failure::MultipleWithRetrySuppression.classes = [Resque::Failure::Redis]
Resque::Failure.backend = Resque::Failure::MultipleWithRetrySuppression
```

If a job fails, but **can and will** retry, the failure details wont be logged
in the Redis failed queue *(visible via resque-web)*.

If the job fails, but **can't or won't** retry, the failure will be logged in
the Redis failed queue, like a normal failure *(without retry)* would.

### Resque Web Additions

If you're using the `MultipleWithRetrySuppression` failure backend, you should
also checkout the `resque-web` additions!

The new Retry tab displays delayed jobs with retry information; the number of
attempts and the exception details from the last failure.


### Configuring and running the Resque-Web Interface

#### Using a Rack configuration:

One alternative is to use a rack configuration file. To use this, make sure you
include this in your `config.ru` or similar file:
```ruby
require 'resque-retry'
require 'resque-retry/server'

# Make sure to require your workers & application code below this line:
# require '[path]/[to]/[jobs]/your_worker'

# Run the server
run Resque::Server.new
```

As an example, you could run this server with the following command:
```
rackup -p 9292 config.ru
```

When using bundler, you can also run the server like this:
```
bundle exec rackup -p 9292 config.ru
```


#### Using the 'resque-web' command with a configuration file:

Another alternative is to use resque's built-in 'resque-web' command with the
additional resque-retry tabs. In order to do this, you must first create a
configuration file. For the sake of this example we'll create the configuration
file in a 'config' directory, and name it 'resque_web_config.rb'. In practice
you could rename this configuration file to anything you like and place in your
project in a directory of your choosing. The contents of the configuration file
would look like this:
```ruby
# [app_dir]/config/resque_web_config.rb
require 'resque-retry'
require 'resque-retry/server'

# Make sure to require your workers & application code below this line:
# require '[path]/[to]/[jobs]/your_worker'
```

Once you have the configuration file ready, you can pass the configuration file
to the resque-web command as a parameter, like so:
```
resque-web [app_dir]/config/resque_web_config.rb
```


Retry Options & Logic
---------------------

Please take a look at the [yardoc](http://rubydoc.info/gems/resque-retry)/code
for more details on methods you may wish to override.

Customisation is pretty easy, the below examples should give you some ideas =),
adapt for your own usage and feel free to pick and mix!

### Retry Defaults

Retry the job **once** on failure, with zero delay.
```ruby
require 'resque-retry'

class DeliverWebHook
  extend Resque::Plugins::Retry
  @queue = :web_hooks

  def self.perform(url, hook_id, hmac_key)
    heavy_lifting
  end
end
```

When a job runs, the number of retry attempts is checked and incremented
in Redis. If your job fails, the number of retry attempts is used to
determine if we can requeue the job for another go.

### Custom Retry
```ruby
class DeliverWebHook
  extend Resque::Plugins::Retry
  @queue = :web_hooks

  @retry_limit = 10
  @retry_delay = 120

  def self.perform(url, hook_id, hmac_key)
    heavy_lifting
  end
end
```

The above modification will allow your job to retry up to 10 times, with a delay
of 120 seconds, or 2 minutes between retry attempts.

You can override the `retry_delay` method to set the delay value dynamically.

### Sleep After Requeuing

Sometimes it is useful to delay the worker that failed a job attempt, but
still requeue the job for immediate processing by other workers. This can be
done with `@sleep_after_requeue`:
```ruby
class DeliverWebHook
  extend Resque::Plugins::Retry
  @queue = :web_hooks

  @sleep_after_requeue = 5

  def self.perform(url, hook_id, hmac_key)
    heavy_lifting
  end
end
```

This retries the job once and causes the worker that failed to sleep for 5
seconds after requeuing the job. If there are multiple workers in the system
this allows the job to be retried immediately while the original worker heals
itself. For example failed jobs may cause other (non-worker) OS processes to
die. A system monitor such as [monit][monit] or [god][god] can fix the server
while the job is being retried on a different worker.

`@sleep_after_requeue` is independent of `@retry_delay`. If you set both, they
both take effect.

You can override the `sleep_after_requeue` method to set the sleep value
dynamically.

### Exponential Backoff

Use this if you wish to vary the delay between retry attempts:
```ruby
class DeliverSMS
  extend Resque::Plugins::ExponentialBackoff
  @queue = :mt_messages

  def self.perform(mt_id, mobile_number, message)
    heavy_lifting
  end
end
```

**Default Settings**
```
key: m = minutes, h = hours

                    0s, 1m, 10m,   1h,    3h,    6h
@backoff_strategy = [0, 60, 600, 3600, 10800, 21600]
@retry_delay_multiplicand_min = 1.0
@retry_delay_multiplicand_max = 1.0
```

The first delay will be 0 seconds, the 2nd will be 60 seconds, etc...  Again,
tweak to your own needs.

The number of retries is equal to the size of the `backoff_strategy` array,
unless you set `retry_limit` yourself.

The delay values will be multiplied by a random `Float` value between
`retry_delay_multiplicand_min` and `retry_delay_multiplicand_max` (both have a
default of `1.0`). The product (`delay_multiplicand`) is recalculated on every
attempt. This feature can be useful if you have a lot of jobs fail at the same
time (e.g. rate-limiting/throttling or connectivity issues) and you don't want
them all retried on the same schedule.

### Retry Specific Exceptions

The default will allow a retry for any type of exception. You may change it so
only specific exceptions are retried using `retry_exceptions`:
```ruby
class DeliverSMS
  extend Resque::Plugins::Retry
  @queue = :mt_messages

  @retry_exceptions = [NetworkError]

  def self.perform(mt_id, mobile_number, message)
    heavy_lifting
  end
end
```

The above modification will **only** retry if a `NetworkError` (or subclass)
exception is thrown.

You may also want to specify different retry delays for different exception
types. You may optionally set `@retry_exceptions` to a hash where the keys are
your specific exception classes to retry on, and the values are your retry
delays in seconds or an array of retry delays to be used similar to exponential
backoff.
```ruby
class DeliverSMS
  extend Resque::Plugins::Retry
  @queue = :mt_messages

  @retry_exceptions = { NetworkError => 30, SystemCallError => [120, 240] }

  def self.perform(mt_id, mobile_number, message)
    heavy_lifting
  end
end
```

In the above example, Resque would retry any `DeliverSMS` jobs which throw a
`NetworkError` or `SystemCallError`. If the job throws a `NetworkError` it
will be retried 30 seconds later, if it throws `SystemCallError` it will first
retry 120 seconds later then subsequent retry attempts 240 seconds later.

### Fail Fast For Specific Exceptions

The default will allow a retry for any type of exception. You may change
it so specific exceptions fail immediately by using `fatal_exceptions`:
```ruby
class DeliverSMS
  extend Resque::Plugins::Retry
  @queue = :mt_divisions

  @fatal_exceptions = [NetworkError]

  def self.perform(mt_id, mobile_number, message)
    heavy_lifting
  end
end
```

In the above example, Resque would retry any `DeliverSMS` jobs that throw any
type of error other than `NetworkError`. If the job throws a `NetworkError` it
will be marked as "failed" immediately.

### Custom Retry Criteria Check Callbacks

You may define custom retry criteria callbacks:
```ruby
class TurkWorker
  extend Resque::Plugins::Retry
  @queue = :turk_job_processor

  @retry_exceptions = [NetworkError]

  retry_criteria_check do |exception, *args|
    if exception.message =~ /InvalidJobId/
      false # don't retry if we got passed a invalid job id.
    else
      true  # its okay for a retry attempt to continue.
    end
  end

  def self.perform(job_id)
    heavy_lifting
  end
end
```

Similar to the previous example, this job will retry if either a
`NetworkError` (or subclass) exception is thrown **or** any of the callbacks
return true.

Use `@retry_exceptions = []` to **only** use callbacks, to determine if the
job should retry.

### Retry Arguments

You may override `retry_args`, which is passed the current job arguments, to
modify the arguments for the next retry attempt.
```ruby
class DeliverViaSMSC
  extend Resque::Plugins::Retry
  @queue = :mt_smsc_messages

  # retry using the emergency SMSC.
  def self.retry_args(smsc_id, mt_message)
    [999, mt_message]
  end

  self.perform(smsc_id, mt_message)
    heavy_lifting
  end
end
```

Alternatively, if you require finer control of the args based on the exception
thrown, you may override `retry_args_for_exception`, which is passed the
exception and the current job arguments, to modify the arguments for the next
retry attempt.
```ruby
class DeliverViaSMSC
  extend Resque::Plugins::Retry
  @queue = :mt_smsc_messages

  # retry using the emergency SMSC.
  def self.retry_args_for_exception(exception, smsc_id, mt_message)
    [999, mt_message + exception.message]
  end

  self.perform(smsc_id, mt_message)
    heavy_lifting
  end
end
```
### Job Retry Identifier/Key

The retry attempt is incremented and stored in a Redis key. The key is built
using the `retry_identifier`. If you have a lot of arguments or really long
ones, you should consider overriding `retry_identifier` to define a more precise
or loose custom retry identifier.

The default identifier is just your job arguments joined with a dash `'-'`.

By default the key uses this format:
`'resque-retry:<job class name>:<retry_identifier>'`.

Or you can define the entire key by overriding `redis_retry_key`.
```ruby
class DeliverSMS
  extend Resque::Plugins::Retry
  @queue = :mt_messages

  def self.retry_identifier(mt_id, mobile_number, message)
    "#{mobile_number}:#{mt_id}"
  end

  self.perform(mt_id, mobile_number, message)
    heavy_lifting
  end
end
```

### Expire Retry Counters From Redis

Allow the Redis to expire stale retry counters from the database by setting
`@expire_retry_key_after`:
```ruby
class DeliverSMS
  extend Resque::Plugins::Retry
  @queue = :mt_messages
  @expire_retry_key_after = 3600 # expire key after `retry_delay` plus 1 hour

  self.perform(mt_id, mobile_number, message)
    heavy_lifting
  end
end
```

This saves you from having to run a "house cleaning" or "errand" job.

The expiary timeout is "pushed forward" or "touched" after each failure to
ensure it's not expired too soon.

### Debug Plugin Logging

The inner-workings of the plugin are output to the Resque [Logger](https://github.com/resque/resque/wiki/Logging)
when `Resque.logger.level` is set to `Logger::DEBUG`.

Contributing/Pull Requests
--------------------------

  * Yes please!
  * Fork the project.
  * Make your feature addition or bug fix.
  * Add tests for it.
  * In a seperate commit, update the HISTORY.md file please.
  * Send us a pull request. Bonus points for topic branches.
  * If you edit the gemspec/version etc, please do so in another commit.

[monit]: https://mmonit.com
[god]: http://godrb.com
[resque]: http://github.com/resque/resque
[resque-scheduler]: http://github.com/resque/resque-scheduler
[bundler]: http://bundler.io
