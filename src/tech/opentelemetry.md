% OpenTelemetry: Building a Custom Collector
% January 21, 2024

OpenTelemetry is an observability framework and toolkit designed to create and manage telemetry data such as traces, metrics, and logs.
It is a set of APIs, SDKs, and tools that enable the generation and collection of application telemetry data.
It is a CNCF project and is the successor to OpenCensus and OpenTracing.

Recently at my "day job",
I have been exploring [OpenTelemetry](https://opentelemetry.io) as part of our observability pipeline.
I have studied the [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/) in some detail, and
have been impressed with its capabilities and the ease of setup.
Although I would be remiss if I didn't mention the project is very much still in its infancy.

# OpenTelemetry Collector

> The OpenTelemetry Collector offers a vendor-agnostic implementation of
> how to receive, process and export telemetry data.
> It removes the need to run, operate, and maintain multiple agents/collectors.

![Fig 1. OpenTelemetry Architecture](https://opentelemetry.io/docs/collector/img/otel-collector.svg)

Without diving too deep into the architecture, the collector is composed of three main components:

- Receivers: scrapes telemetry data at regular intervals from a source
- Processors: transforms the data as needed
- Exporters: sends the data to a destination

# Building a custom OpenTelemetry Collector

For this POC, I wanted to build a custom collector that scrapes **virtual memory metrics** and exports them to Kafka.
Let's see how we can leverage the OpenTelemetry Collector to build this pipeline.

## Step 0: Install the prerequisites

Make sure you have Go installed on your system. This tutorial is using Go 1.21.
We need two otel (OpenTelemetry) tools to build our collector:

- `builder`: to build the collector binary
- `mdatagen`: to generate the boilerplate code for the receiver

```bash
go install go.opentelemetry.io/collector/cmd/builder@latest
go install go.opentelemetry.io/collector/cmd/mdatagen@latest
```

Make sure the Go binary directory is exported in your `PATH`.

```bash
export PATH=$PATH:$(go env GOPATH)/bin
```

## Step 1: Define the receiver

The first component we need to build is the receiver. We are calling it `vmreceiver` for obvious reasons.
Any otel component is defined using a `metadata.yaml` file.
This file defines the `metrics` (or `logs` or `traces`) that the component will collect and their dimensions (`attributes`).

Let's create a `metadata.yaml` file for our receiver at `receivers/vmreceiver/`:

```yaml
type: vmstats

status:
  class: receiver
  stability:
    alpha: [metrics]
  distributions: [contrib]

attributes:
  hostname:
    description: Hostname of the machine
    type: string
  ...

metrics:
  swapped:
    enabled: true
    description: Amount of virtual memory used
    type: bytes
    gauge:
      value_type: int
    attributes:
      - hostname
  free:
    enabled: true
    description: Amount of idle memory
    unit: bytes
    gauge:
      value_type: int
    attributes:
      - hostname
  ...
```

The entire schema is defined [here](https://github.com/mmynk/otel-kafka-poc/blob/main/receivers/vmreceiver/metadata.yaml).

Now that we have defined the receiver metadata, we can generate the boilerplate code for the receiver
using otel tool `mdatagen`:

```bash
$ cd receivers/vmreceiver
$ mdatagen metadata.yaml
```

We are now ready to write our receiver code. We will use [vmstat](https://man7.org/linux/man-pages/man8/vmstat.8.html) to scrape the virtual memory metrics.
Let's start by defining the config which contains any tuning parameters for the receiver:

```go
// config.go

type Config struct {
	// Delay is the delay between `vmstat` calls
	Delay int `mapstructure:"delay"`
	// Count is the number of `vmstat` calls to make
	Count int `mapstructure:"count"`

	// MetricsBuilderConfig to enable/disable specific metrics (default: all enabled)
	metadata.MetricsBuilderConfig `mapstructure:",squash"`
	// ScraperControllerSettings to configure scraping interval (default: scrape every second)
	scraperhelper.ScraperControllerSettings `mapstructure:",squash"`
}
```
The last two fields are embedded structs that we can use to configure the metrics and the scraping interval.

Let's now write a simple `vmstat` wrapper that will scrape the metrics.

```go
// stat.go

type vmStat struct {
    Swapped         int64
    Free            int64
}

type vmStatReader struct {
    delay int
    count int

    logger *zap.Logger
}

func (r *vmStatReader) Read() (*vmStat, error) {
    cmd := exec.Command("vmstat", fmt.Sprintf("%d", r.delay), fmt.Sprintf("%d", r.count))
    out, err := cmd.Output()
    if err != nil {
        r.logger.Error("failed to execute vmstat", zap.Error(err))
        return nil, err
    }
    return r.parse(out)
}

func (r *vmStatReader) parse(out []byte) (*vmStat, error) {
	// parse the output of vmstat
}
```

Simple enough. Now let's write the `scraper` that will use the `vmStatReader` to scrape the metrics.
The method `scrape` is called at regular intervals by the collector.

```go
// scraper.go

type scraper struct {
	logger         *zap.Logger              // Logger to log events
	metricsBuilder *metadata.MetricsBuilder // MetricsBuilder to build metrics
	reader         *vmStatReader            // vmStatReader to read vmstat output
}

func newScraper(cfg *Config, metricsBuilder *metadata.MetricsBuilder, logger *zap.Logger) *scraper {
	return &scraper{
		logger:         logger,
		metricsBuilder: metricsBuilder,
		reader:         newVmStatReader(cfg, logger),
	}
}

func (s *scraper) scrape(_ context.Context) (pmetric.Metrics, error) {
	vmStat, err := s.reader.Read()
	if err != nil {
		return pmetric.Metrics{}, err
	}
	attr := newAttributeReader(s.logger).getAttributes()
	s.recordVmStats(vmStat, attr)
	return s.metricsBuilder.Emit(), nil
}

func (s *scraper) recordVmStats(stat *vmStat, attr *attributes) {
	now := pcommon.NewTimestampFromTime(time.Now())

	s.metricsBuilder.RecordSwappedDataPoint(now, stat.Swapped, attr.host, attr.os, attr.arch, "memory")
	s.metricsBuilder.RecordFreeDataPoint(now, stat.Free, attr.host, attr.os, attr.arch, "memory")
}
```

Now finally, we can define a `Factory` that will be the entrypoint for the receiver.
Here we plug in the `scraper` into the collector's receiver.

```go
// factory.go

func NewFactory() receiver.Factory {
	return receiver.NewFactory(
		metadata.Type,
		createDefaultConfig,
		receiver.WithMetrics(CreateVmStatReceiver, component.StabilityLevelDevelopment),
	)
}

func CreateVmStatReceiver(
	_ context.Context,
	settings receiver.CreateSettings,
	cfg component.Config,
	consumer consumer.Metrics,
) (receiver.Metrics, error) {
	logger := settings.Logger
	config, ok := cfg.(*Config)
	if !ok {
		em := "failed to cast to type Config"
		logger.Error(em)
		return nil, fmt.Errorf(em)
	}

	mb := metadata.NewMetricsBuilder(config.MetricsBuilderConfig, settings)

	ns := newScraper(config, mb, logger)
	scraper, err := scraperhelper.NewScraper(metadata.Type, ns.scrape)
	if err != nil {
		logger.Error("failed to create scraper", zap.Error(err))
		return nil, err
	}

	return scraperhelper.NewScraperControllerReceiver(
		&config.ScraperControllerSettings,
		settings,
		consumer,
		scraperhelper.AddScraper(scraper),
	)
}
```

Well, that's about it. Our receiver is ready to start scraping metrics.

## Step 2: Define the configs

We need two configuration files for an OpenTelemetry Collector (obviously, the names are arbitrary):

- `builder-config.yaml`: defines the components of the collector
- `otelcol.yaml`: defines the configuration of each of the components

```yaml
# builder-config.yaml
receivers:
  - gomod: github.com/mmynk/otel-kafka-poc/receivers/vmreceiver v0.0.1
    import: github.com/mmynk/otel-kafka-poc/receivers/vmreceiver
    name: 'vmreceiver'
    path: './receivers/vmreceiver'
```

```yaml
# otelcol.yaml

receivers:
  vmstats:
    collection_interval: 10s
    delay: 2
    count: 2
```

Before we write our own exporter, we can actually deploy our collector by using a pre-built exporter
from the [OpenTelemetry Collector Contrib](https://github.com/open-telemetry/opentelemetry-collector-contrib) repo.
Let's add the [Prometheus exporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/prometheusexporter) to our pipeline.

```yaml
# builder-config.yaml
exporters:
  - gomod: github.com/open-telemetry/opentelemetry-collector-contrib/exporter/prometheusexporter v0.92.0

# otelcol.yaml
exporters:
  prometheus:
    endpoint: 0.0.0.0:8889

service:
    pipelines:
        metrics:
        receivers: [vmstats]
        exporters: [prometheus]
```

## Step 3: Deploy the collector

Let's fire up the collector and see if it works.

```bash
$ builder --config builder-config.yaml
...
2024-01-22T01:02:53.018Z	INFO	builder/main.go:121	Compiled	{"binary": "./otelcol-dev/otelcol"}
```
This will generate a binary `otelcol-dev/otelcol` in the current directory.

If everything went well, we should be able to run the binary.

```bash
$ ./otelcol-dev/otelcol --config otelcol.yaml
...
2024-01-22T01:04:20.061Z	info	service@v0.92.0/telemetry.go:159	Serving metrics	{"address": ":8888", "level": "Basic"}
...
2024-01-22T01:04:20.062Z	info	service@v0.92.0/service.go:177	Everything is ready. Begin running and processing data.
```

We should now be able to see the metrics at `http://localhost:8888/metrics`.

Yay! We have successfully built a custom OpenTelemetry collector.

## Step 4: Build a custom exporter

TODO

# Links

All the code used in this tutorial is available in the GitHub repo [mmynk/otel-kafka-poc](https://github.com/mmynk/otel-kafka-poc).
