require 'spec_helper'

describe Datadog::Statsd do
  let(:socket) { FakeUDPSocket.new }

  subject do
    described_class.new('localhost', 1234,
      namespace: namespace,
      sample_rate: sample_rate,
      tags: tags,
      logger: logger,
      telemetry_flush_interval: -1,
    )
  end

  let(:namespace) { 'sample_ns' }
  let(:sample_rate) { nil }
  let(:tags) { %w[abc def] }
  let(:logger) do
    Logger.new(log).tap do |logger|
      logger.level = Logger::INFO
    end
  end
  let(:log) { StringIO.new }

  before do
    allow(Socket).to receive(:new).and_return(socket)
    allow(UDPSocket).to receive(:new).and_return(socket)
  end

  describe '#initialize' do
    context 'when using provided values' do
      it 'sets the host correctly' do
        expect(subject.connection.host).to eq 'localhost'
      end

      it 'sets the port correctly' do
        expect(subject.connection.port).to eq 1234
      end

      it 'sets the namespace' do
        expect(subject.namespace).to eq 'sample_ns'
      end

      it 'sets the right tags' do
        expect(subject.tags).to eq %w[abc def]
      end

      context 'when using tags in a hash' do
        let(:tags) do
          {
            one: 'one',
            two: 'two',
          }
        end

        it 'sets the right tags' do
          expect(subject.tags).to eq %w[one:one two:two]
        end
      end
    end

    context 'when using environment variables' do
      subject do
        described_class.new(
          namespace: namespace,
          sample_rate: sample_rate,
          tags: %w[abc def]
        )
      end

      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('DD_AGENT_HOST', anything).and_return('myhost')
        allow(ENV).to receive(:fetch).with('DD_DOGSTATSD_PORT', anything).and_return(4321)
        allow(ENV).to receive(:fetch).with('DD_ENTITY_ID', anything).and_return('04652bb7-19b7-11e9-9cc6-42010a9c016d')
      end

      it 'sets the host using the env var DD_AGENT_HOST' do
        expect(subject.connection.host).to eq 'myhost'
      end

      it 'sets the port using the env var DD_DOGSTATSD_PORT' do
        expect(subject.connection.port).to eq 4321
      end

      it 'sets the entity tag using ' do
        expect(subject.tags).to eq [
          'abc',
          'def',
          'dd.internal.entity_id:04652bb7-19b7-11e9-9cc6-42010a9c016d'
        ]
      end
    end

    context 'when using default values' do
      subject do
        described_class.new
      end

      it 'sets the host to default values' do
        expect(subject.connection.host).to eq '127.0.0.1'
      end

      it 'sets the port to default values' do
        expect(subject.connection.port).to eq 8125
      end

      it 'sets no namespace' do
        expect(subject.namespace).to be_nil
      end

      it 'sets no tags' do
        expect(subject.tags).to be_empty
      end
    end

    context 'when testing connection type' do
      let(:fake_socket) do
        FakeUDPSocket.new
      end

      context 'when using a host and a port' do
        before do
          allow(UDPSocket).to receive(:new).and_return(fake_socket)
        end

        it 'uses an UDP socket' do
          expect(subject.connection.send(:socket)).to be fake_socket
        end
      end

      context 'when using a socket_path' do
        subject do
          described_class.new(
            namespace: namespace,
            sample_rate: sample_rate,
            socket_path: '/tmp/socket'
          )
        end

        before do
          allow(Socket).to receive(:new).and_call_original
        end

        it 'uses an UDS socket' do
          expect do
            subject.connection.send(:socket)
          end.to raise_error(Errno::ENOENT, /No such file or directory - connect\(2\)/)
        end
      end
    end
  end

  describe '#open' do
    before do
      allow(described_class)
        .to receive(:new)
        .and_return(fake_statsd)
    end

    let(:fake_statsd) do
      instance_double(described_class, close: true)
    end

    it 'builds an instance of statsd correctly' do
      expect(described_class)
        .to receive(:new)
        .with('localhost', 1234,
          namespace: namespace,
          sample_rate: sample_rate,
          tags: tags,
        )

      described_class.open('localhost', 1234,
        namespace: namespace,
        sample_rate: sample_rate,
        tags: tags,
      ) {}
    end

    it 'yields the statsd instance' do
      expect do |block|
        described_class.open(&block)
      end.to yield_with_args(fake_statsd)
    end

    it 'closes the statsd instance' do
      expect(fake_statsd).to receive(:close)

      described_class.open {}
    end


    it 'ensures the statsd instance is closed' do
      expect(fake_statsd).to receive(:close)

      described_class.open do
        raise 'stop'
      end rescue nil
    end
  end

  describe '#increment' do
    let(:namespace) { nil }
    let(:sample_rate) { nil }
    let(:tags) { nil }

    it_behaves_like 'a metrics method', 'foobar:1|c' do
      let(:basic_action) do
        subject.increment('foobar', tags: action_tags)
      end
    end

    it 'sends the increment' do
      subject.increment('foobar')

      expect(socket.recv[0]).to eq_with_telemetry('foobar:1|c')
    end

    context 'with a sample rate' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'formats the message according to the statsd spec' do
        subject.increment('foobar', sample_rate: 0.5)
        expect(socket.recv[0]).to eq_with_telemetry 'foobar:1|c|@0.5'
      end
    end

    context 'with a sample rate like statsd-ruby' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'sends the increment with the sample rate' do
        subject.increment('foobar', 0.5)
        expect(socket.recv[0]).to eq_with_telemetry 'foobar:1|c|@0.5'
      end
    end

    context 'with a increment by' do
      it 'increments by the number given' do
        subject.increment('foobar', by: 5)
        expect(socket.recv[0]).to eq_with_telemetry 'foobar:5|c'
      end
    end
  end

  describe '#decrement' do
    let(:namespace) { nil }
    let(:sample_rate) { nil }
    let(:tags) { nil }

    it_behaves_like 'a metrics method', 'foobar:-1|c' do
      let(:basic_action) do
        subject.decrement('foobar', tags: action_tags)
      end
    end

    it 'sends the decrement' do
      subject.decrement('foobar')
      expect(socket.recv[0]).to eq_with_telemetry 'foobar:-1|c'
    end

    context 'with a sample rate' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'sends the decrement with the sample rate' do
        subject.decrement('foobar', sample_rate: 0.5)
        expect(socket.recv[0]).to eq_with_telemetry 'foobar:-1|c|@0.5'
      end
    end

    context 'with a sample rate like statsd-ruby' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'sends the decrement with the sample rate' do
        subject.decrement('foobar', 0.5)
        expect(socket.recv[0]).to eq_with_telemetry 'foobar:-1|c|@0.5'
      end
    end

    context 'with a decrement by' do
      it 'decrements by the number given' do
        subject.decrement('foobar', by: 5)
        expect(socket.recv[0]).to eq_with_telemetry 'foobar:-5|c'
      end
    end
  end

  describe '#count' do
    let(:namespace) { nil }
    let(:sample_rate) { nil }
    let(:tags) { nil }

    it_behaves_like 'a metrics method', 'foobar:123|c' do
      let(:basic_action) do
        subject.count('foobar', 123, tags: action_tags)
      end
    end

    it 'sends the count' do
      subject.count('foobar', 123)
      expect(socket.recv[0]).to eq_with_telemetry 'foobar:123|c'
    end

    context 'with a sample rate like statsd-ruby' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'sends the count with sample rate' do
        subject.count('foobar', 123, 0.1)
        expect(socket.recv[0]).to eq_with_telemetry 'foobar:123|c|@0.1'
      end
    end
  end

  describe '#gauge' do
    let(:namespace) { nil }
    let(:sample_rate) { nil }
    let(:tags) { nil }

    it_behaves_like 'a metrics method', 'begrutten-suffusion:536|g' do
      let(:basic_action) do
        subject.gauge('begrutten-suffusion', 536, tags: action_tags)
      end
    end

    it 'sends the gauge' do
      subject.gauge('begrutten-suffusion', 536)
      expect(socket.recv[0]).to eq_with_telemetry 'begrutten-suffusion:536|g'
    end

    it 'sends the gauge with sequential values' do
      subject.gauge('begrutten-suffusion', 536)
      expect(socket.recv[0]).to eq_with_telemetry 'begrutten-suffusion:536|g'

      subject.gauge('begrutten-suffusion', -107.3)
      expect(socket.recv[0]).to eq_with_telemetry 'begrutten-suffusion:-107.3|g', bytes_sent: 697, packets_sent: 1
    end

    context 'with a sample rate' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'sends the gauge with the sample rate' do
        subject.gauge('begrutten-suffusion', 536, sample_rate: 0.1)
        expect(socket.recv[0]).to eq_with_telemetry 'begrutten-suffusion:536|g|@0.1'
      end
    end

    describe 'with a sample rate like statsd-ruby' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'formats the message according to the statsd spec' do
        subject.gauge('begrutten-suffusion', 536, 0.1)
        expect(socket.recv[0]).to eq_with_telemetry 'begrutten-suffusion:536|g|@0.1'
      end
    end
  end

  describe '#histogram' do
    let(:namespace) { nil }
    let(:sample_rate) { nil }
    let(:tags) { nil }

    it_behaves_like 'a metrics method', 'ohmy:536|h' do
      let(:basic_action) do
        subject.histogram('ohmy', 536, tags: action_tags)
      end
    end

    it 'sends the histogram' do
      subject.histogram('ohmy', 536)
      expect(socket.recv[0]).to eq_with_telemetry 'ohmy:536|h'
    end

    it 'sends the histogram with sequential values' do
      subject.histogram('ohmy', 536)
      expect(socket.recv[0]).to eq_with_telemetry 'ohmy:536|h'

      subject.histogram('ohmy', -107.3)
      expect(socket.recv[0]).to eq_with_telemetry 'ohmy:-107.3|h', bytes_sent: 682, packets_sent: 1
    end

    context 'with a sample rate' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'sends the histogram with the sample rate' do
        subject.gauge('begrutten-suffusion', 536, sample_rate: 0.1)
        expect(socket.recv[0]).to eq_with_telemetry 'begrutten-suffusion:536|g|@0.1'
      end
    end
  end

  describe '#set' do
    let(:namespace) { nil }
    let(:sample_rate) { nil }
    let(:tags) { nil }

    it_behaves_like 'a metrics method', 'myset:536|s' do
      let(:basic_action) do
        subject.set('myset', 536, tags: action_tags)
      end
    end

    it 'sends the set' do
      subject.set('my.set', 536)
      expect(socket.recv[0]).to eq_with_telemetry 'my.set:536|s'
    end

    context 'with a sample rate' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'sends the set with the sample rate' do
        subject.set('my.set', 536, sample_rate: 0.5)
        expect(socket.recv[0]).to eq_with_telemetry 'my.set:536|s|@0.5'
      end
    end

    context 'with a sample rate like statsd-ruby' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'sends the set with the sample rate' do
        subject.set('my.set', 536, 0.5)
        expect(socket.recv[0]).to eq_with_telemetry 'my.set:536|s|@0.5'
      end
    end
  end

  describe '#timing' do
    let(:namespace) { nil }
    let(:sample_rate) { nil }
    let(:tags) { nil }

    it_behaves_like 'a metrics method', 'foobar:500|ms' do
      let(:basic_action) do
        subject.timing('foobar', 500, tags: action_tags)
      end
    end

    it 'sends the timing' do
      subject.timing('foobar', 500)
      expect(socket.recv[0]).to eq_with_telemetry 'foobar:500|ms'
    end

    context 'with a sample rate' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'sends the timing with the sample rate' do
        subject.timing('foobar', 500, sample_rate: 0.5)
        expect(socket.recv[0]).to eq_with_telemetry 'foobar:500|ms|@0.5'
      end
    end

    context 'with a sample rate like statsd-ruby' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'sends the timing with the sample rate' do
        subject.timing('foobar', 500, 0.5)
        expect(socket.recv[0]).to eq_with_telemetry 'foobar:500|ms|@0.5'
      end
    end
  end

  describe '#time' do
    let(:namespace) { nil }
    let(:sample_rate) { nil }
    let(:tags) { nil }

    let(:before_date) do
      DateTime.new(2020, 2, 25, 12, 12, 12)
    end

    let(:after_date) do
      DateTime.new(2020, 2, 25, 12, 12, 13)
    end

    before do
      Timecop.freeze(before_date)
      allow(Process).to receive(:clock_gettime).and_return(0, 1)
    end

    it_behaves_like 'a metrics method', 'foobar:1000|ms' do
      let(:basic_action) do
        subject.time('foobar', tags: action_tags) do
          Timecop.travel(after_date)
        end
      end
    end

    context 'when actually testing time' do
      it 'sends the timing' do
        subject.time('foobar') do
          Timecop.travel(after_date)
        end

        expect(socket.recv[0]).to eq_with_telemetry 'foobar:1000|ms'
      end

      it 'ensures the timing is sent' do
        subject.time('foobar') do
          Timecop.travel(after_date)
          raise 'stop'
        end rescue nil

        expect(socket.recv[0]).to eq_with_telemetry 'foobar:1000|ms'
      end
    end

    it 'returns the result of the block' do
      expect(subject.time('foobar') { 'test' }).to eq 'test'
    end

    it 'does not catch errors if block is failing' do
      expect do
        subject.time('foobar') do
          raise 'yolo'
        end
      end.to raise_error(StandardError, 'yolo')
    end

    it 'can run without "PROCESS_TIME_SUPPORTED"' do
      stub_const('PROCESS_TIME_SUPPORTED', false)

      expect do
        subject.time('foobar') {}
      end.not_to raise_error
    end

    context 'with a sample rate' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'sends the timing with the sample rate' do
        subject.time('foobar', sample_rate: 0.5) do
          Timecop.travel(after_date)
        end

        expect(socket.recv[0]).to eq_with_telemetry 'foobar:1000|ms|@0.5'
      end
    end

    context 'with a sample rate like statsd-ruby' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'sends the timing with the sample rate' do
        subject.time('foobar', 0.5) do
          Timecop.travel(after_date)
        end

        expect(socket.recv[0]).to eq_with_telemetry 'foobar:1000|ms|@0.5'
      end
    end
  end

  describe '#distribution' do
    let(:namespace) { nil }
    let(:sample_rate) { nil }
    let(:tags) { nil }

    it_behaves_like 'a metrics method', 'begrutten-suffusion:536|d' do
      let(:basic_action) do
        subject.distribution('begrutten-suffusion', 536, tags: action_tags)
      end
    end

    it 'sends the distribution' do
      subject.distribution('begrutten-suffusion', 536)
      expect(socket.recv[0]).to eq_with_telemetry 'begrutten-suffusion:536|d'
    end

    context 'with a sample rate' do
      before do
        allow(subject).to receive(:rand).and_return(0)
      end

      it 'sends the set with the sample rate' do
        subject.distribution('begrutten-suffusion', 536, sample_rate: 0.5)
        expect(socket.recv[0]).to eq_with_telemetry 'begrutten-suffusion:536|d|@0.5'
      end
    end
  end
end