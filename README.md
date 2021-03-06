# Sluice

Sluice is a Ruby gem (built with [Bundler] [bundler]) to help you build cloud-friendly ETL (extract, transform, load) processes.

**Currently it does one thing: supports very robust, very parallel copy/delete/move of S3 files from one bucket to another.**

Sluice has been extracted from a pair of Ruby ETL applications built by the [SnowPlow Analytics] [snowplow-analytics] team, specifically:

1. [EmrEtlRunner] [emr-etl-runner], a Ruby application to run the SnowPlow ETL process on Elastic MapReduce
2. [StorageLoader] [storage-loader], a Ruby application to load SnowPlow event files from Amazon S3 into databases such as Infobright

## Installation 

    $ gem install sluice

Or in your Gemfile:

    gem 'sluice', '~> 0.0.6'

## Usage

Rubydoc and usage examples to come.

## Hacking and contributing

To hack on Sluice locally:

    $ gem build sluice.gemspec
    $ sudo gem install sluice-0.0.6.gem

To contribute:

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Credits and thanks

Sluice was developed by [Alex Dean] [alexanderdean] ([SnowPlow Analytics] [snowplow-analytics]) and [Michael Tibben] [mtibben] ([99designs] [99designs]).

## Copyright and license

Sluice is copyright 2012 SnowPlow Analytics Ltd.

Licensed under the [Apache License, Version 2.0] [license] (the "License");
you may not use this software except in compliance with the License.

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

[bundler]: http://gembundler.com/

[snowplow-analytics]: http://snowplowanalytics.com
[alexanderdean]: https://github.com/alexanderdean
[mtibben]: https://github.com/mtibben
[99designs]: http://99designs.com

[emr-etl-runner]: https://github.com/snowplow/snowplow/tree/master/3-etl/emr-etl-runner
[storage-loader]: https://github.com/snowplow/snowplow/tree/master/4-storage/storage-loader

[license]: http://www.apache.org/licenses/LICENSE-2.0
