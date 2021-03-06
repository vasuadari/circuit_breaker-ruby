require 'spec_helper'
require 'circuit_breaker-ruby'
require 'timecop'

describe CircuitBreaker::Shield do
  context 'with no failures' do
    it 'goes to closed state' do
      circuit_breaker_shield = CircuitBreaker::Shield.new(
        invocation_timeout: 1,
        retry_timeout: 1,
        failure_threshold: 1
      )

      circuit_breaker_shield.protect { sleep(0.1) } # succeed once
      expect(circuit_breaker_shield.total_count).to eql(1)
      expect(circuit_breaker_shield.failure_count).to eql(0)
      expect(circuit_breaker_shield.send(:state)).to be(CircuitBreaker::Shield::States::CLOSED)
    end
  end

  context 'with failures less than threshold' do
    it 'goes to closed state' do
      retry_timeout = 1

      circuit_breaker_shield = CircuitBreaker::Shield.new(
        invocation_timeout: 1,
        retry_timeout: retry_timeout,
        failure_threshold: 2
      )

      circuit_breaker_shield.protect { sleep(0.1) } # succeed once
      expect(circuit_breaker_shield.total_count).to eql(1)
      expect(circuit_breaker_shield.failure_count).to eql(0)

      expect {circuit_breaker_shield.protect { sleep(1.1) }}.to raise_error(CircuitBreaker::TimeoutError) # fail once
      expect(circuit_breaker_shield.total_count).to eql(2)
      expect(circuit_breaker_shield.failure_count).to eql(1)
      expect(circuit_breaker_shield.send(:state)).to be(CircuitBreaker::Shield::States::CLOSED)
    end
  end

  context 'with failures more than threshold' do
    context 'within retry_timeout' do
      it 'goes to open state' do
        circuit_breaker_shield = CircuitBreaker::Shield.new(
          invocation_timeout: 1,
          retry_timeout: 1,
          failure_threshold: 1
        )

        circuit_breaker_shield.protect { sleep(0.1) } # succeed once
        expect(circuit_breaker_shield.total_count).to eql(1)
        expect(circuit_breaker_shield.failure_count).to eql(0)

        expect { circuit_breaker_shield.protect { sleep(1.1) } }.to raise_error(CircuitBreaker::TimeoutError) # fail once
        expect(circuit_breaker_shield.total_count).to eql(2)
        expect(circuit_breaker_shield.failure_count).to eql(1)

        expect { circuit_breaker_shield.protect { sleep(1.1) } }.to raise_error(CircuitBreaker::Open) # fail twice
        expect(circuit_breaker_shield.total_count).to eql(2)
        expect(circuit_breaker_shield.failure_count).to eql(1)

        expect(circuit_breaker_shield.send(:state)).to be(CircuitBreaker::Shield::States::OPEN)
      end
    end

    context 'after retry_timeout' do
      it 'goes to half open state' do
        retry_timeout = 1

        circuit_breaker_shield = CircuitBreaker::Shield.new(
          invocation_timeout: 1,
          retry_timeout: retry_timeout,
          failure_threshold: 1
        )

        circuit_breaker_shield.protect { sleep(0.1) } # succeed once
        expect(circuit_breaker_shield.total_count).to eql(1)
        expect(circuit_breaker_shield.failure_count).to eql(0)

        expect {circuit_breaker_shield.protect { sleep(1.1) }}.to raise_error(CircuitBreaker::TimeoutError) # fail once
        expect(circuit_breaker_shield.total_count).to eql(2)
        expect(circuit_breaker_shield.failure_count).to eql(1)


        Timecop.freeze(Time.now + retry_timeout) do
          expect(circuit_breaker_shield.send(:state)).to be(CircuitBreaker::Shield::States::HALF_OPEN)
        end
      end
    end
  end

  context '#protect' do
    it 'update invocation_timeout in config' do
      circuit_breaker_shield = CircuitBreaker::Shield.new(
        invocation_timeout: 1,
        retry_timeout: 1,
        failure_threshold: 1
      )

      circuit_breaker_shield.protect(invocation_timeout: 20) {}

      expect(circuit_breaker_shield.invocation_timeout).to be(20)
    end

    it 'invokes callback on success' do
      callback = proc { 'Success' }
      circuit_breaker_shield = CircuitBreaker::Shield.new(
        invocation_timeout: 1,
        retry_timeout: 1,
        failure_threshold: 1,
        callback: callback
      )

      expect(callback).to receive(:call).and_return('Success')

      circuit_breaker_shield.protect { { response: 'Dummy response' } }
    end

    context 'with timeout error' do
      it 're-raises timeout error' do
        circuit_breaker_shield = CircuitBreaker::Shield.new(
          invocation_timeout: 1,
          retry_timeout: 1,
          failure_threshold: 1
        )

        invocation_block = proc{ raise Timeout::Error }

        expect {circuit_breaker_shield.protect(&invocation_block)}.to raise_error(CircuitBreaker::TimeoutError)
      end
    end
  end
end
