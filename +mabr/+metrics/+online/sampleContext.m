function ctx = sampleContext()
% mabr.metrics.online.sampleContext  A representative metric context.
%
%   ctx = mabr.metrics.online.sampleContext returns the context struct a
%   metric would see partway through a real run: 64 clean sweeps of a decaying
%   evoked-looking response on deterministic noise, sampled at the ADC rate,
%   carrying a 10 ms pre-onset baseline, windowed to [0 10] ms, with a
%   populated Params struct and a couple of rejected sweeps in the
%   bookkeeping.
%
%   It exists so mabr.metrics.online.validate has something honest to test an
%   unknown function against, and so anyone writing a metric can develop it at
%   the command line without an acquisition:
%
%       ctx = mabr.metrics.online.sampleContext;
%       v   = my_metric(ctx)
%
%   Deterministic (no rng): the same context every time, so a metric that
%   passes validation once passes it again.
%
% Daniel Stolzberg (c) 2019-2026

Fs   = 12000;
tPre = (-round(0.010*Fs):-1)/Fs;
tPost= (0:round(0.010*Fs))/Fs;
t    = [tPre tPost]';

nSweeps = 64;
wave    = [zeros(1,numel(tPre)) sin(2*pi*750*tPost).*exp(-tPost/0.003)]';
sweeps  = zeros(numel(t),nSweeps);
for k = 1:nSweeps
    noise = 2e-7*sin(2*pi*(37+k)*(1:numel(t))'/Fs);
    sweeps(:,k) = 5e-7*wave + noise;
end

info = struct('Window',[0 10],'Label','8 kHz, 60 dB','ID','8kHz_60dB', ...
    'Params',struct('Frequency',8,'Level',60), ...
    'NumTotal',nSweeps+3,'NumArtifacts',3,'Live',true);

ctx = mabr.metrics.online.context(sweeps,t,Fs,info);
end
