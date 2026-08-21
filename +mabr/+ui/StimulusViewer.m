classdef StimulusViewer < handle
% mabr.ui.StimulusViewer  Inspect the waveforms in a loaded stimulus bank.
%
%   MABR plays whatever the external stimulus package hands it, sight unseen.
%   This viewer is the "sight": it lists every entry in a mabr.stim.StimulusSet
%   and plots the selected waveform(s) in time and in frequency, so an operator
%   can confirm the bank is the one they meant to load before committing a
%   subject to it.
%
%       sv = mabr.ui.StimulusViewer(set);   % own figure, first entry shown
%       sv.setStimuli(otherSet);            % swap the bank being viewed
%       sv.show();                          % raise (rebuilds a closed figure)
%
%   Select several entries to overlay them. The spectra of an overlay share one
%   0 dB reference -- the loudest of the selection -- so level differences
%   between entries stay visible instead of each curve being normalized flat.
%
%   The viewer is read-only and holds no state of its own beyond the selection:
%   it never modifies the bank, and mabr.ui.App simply pushes a new set into it
%   whenever one is loaded.
%
%   See also mabr.stim.StimulusSet, mabr.ui.App.
%
% Daniel Stolzberg (c) 2019-2026

    properties (SetAccess = private)
        Stimuli  mabr.stim.StimulusSet
        Figure                              % readable so callers can export it
    end

    properties (Access = private)
        List
        Info
        axWave
        axSpec
    end

    methods
        function obj = StimulusViewer(set)
            if nargin >= 1 && ~isempty(set), obj.Stimuli = set; end
            obj.show();
        end

        function delete(obj)
            if ~isempty(obj.Figure) && isgraphics(obj.Figure), delete(obj.Figure); end
        end

        function setStimuli(obj,set)
            % Adopt a new bank. The selection cannot survive a different bank,
            % so it resets to the first entry.
            obj.Stimuli = set;
            obj.refresh(true);
        end

        function show(obj)
            % Raise the window, building it first if it was closed.
            if ~obj.isvalidView()
                obj.build();
                obj.refresh(true);
            end
            figure(obj.Figure);
        end

        function tf = isvalidView(obj)
            tf = ~isempty(obj.Figure) && isgraphics(obj.Figure);
        end
    end

    % ===================================================================
    methods (Access = private)
        function build(obj)
            obj.Figure = uifigure('Name','MABR Stimulus Viewer', ...
                'Position',[100 100 820 500],'Tag','MABR_STIMVIEWER');

            g = uigridlayout(obj.Figure,[1 2]);
            g.ColumnWidth   = {240,'1x'};
            g.RowHeight     = {'1x'};
            g.Padding       = [8 8 8 8];
            g.ColumnSpacing = 8;

            % Left: what is in the bank. The details pane is fixed-height so
            % the list keeps every pixel the window can spare -- a long bank is
            % the case that actually needs the room.
            left = uigridlayout(g,[2 1]);
            left.RowHeight  = {'1x',150};
            left.Padding    = [0 0 0 0];
            left.RowSpacing = 6;

            obj.List = uilistbox(left,'Items',{},'Multiselect','on', ...
                'Tooltip','Select one or more stimuli to plot; the overlay shares one dB reference.', ...
                'ValueChangedFcn',@(~,~) obj.draw());
            obj.Info = uitextarea(left,'Editable','off','FontName','monospaced', ...
                'Value',{''});

            % Right: the two views of the selection, same height each.
            right = uigridlayout(g,[2 1]);
            right.RowHeight  = {'1x','1x'};
            right.Padding    = [0 0 0 0];
            right.RowSpacing = 8;

            obj.axWave = uiaxes(right);
            xlabel(obj.axWave,'Time (ms)');
            ylabel(obj.axWave,'Amplitude');
            grid(obj.axWave,'on'); box(obj.axWave,'on');

            obj.axSpec = uiaxes(right);
            xlabel(obj.axSpec,'Frequency (kHz)');
            ylabel(obj.axSpec,'Magnitude (dB re peak)');
            grid(obj.axSpec,'on'); box(obj.axSpec,'on');
            obj.axSpec.XScale = 'log';
        end

        function n = count(obj)
            n = 0;
            if ~isempty(obj.Stimuli) && isvalid(obj.Stimuli)
                n = obj.Stimuli.numStimuli;
            end
        end

        function refresh(obj,resetSelection)
            % Rebuild the list from the bank, then redraw. Keeps the current
            % selection where the new bank is long enough to hold it.
            if nargin < 2, resetSelection = false; end
            if ~obj.isvalidView(), return; end

            n = obj.count();
            if n == 0
                obj.List.ItemsData = [];
                obj.List.Items     = {};
                obj.List.Enable    = 'off';
                obj.Info.Value = { ...
                    'No stimulus bank loaded.'; ''; ...
                    'Load one in the MABR window'; ...
                    '("Load .mat…" or "Test Stimulus").'};
                obj.clearAxes();
                return
            end

            sel = [];
            if ~resetSelection && isnumeric(obj.List.Value), sel = obj.List.Value; end

            ids   = obj.Stimuli.IDs();
            items = cell(1,n);
            for i = 1:n, items{i} = sprintf('%d. %s',i,ids{i}); end

            % Items and ItemsData must always agree in length, so clear the
            % data before the (differently sized) items go in.
            obj.List.ItemsData = [];
            obj.List.Items     = items;
            obj.List.ItemsData = 1:n;
            obj.List.Enable    = 'on';

            sel = sel(sel >= 1 & sel <= n);
            if isempty(sel), sel = 1; end
            obj.List.Value = sel;

            obj.draw();
        end

        function draw(obj)
            if ~obj.isvalidView(), return; end
            idx = obj.List.Value;
            if obj.count() == 0 || isempty(idx) || ~isnumeric(idx)
                obj.clearAxes(); return
            end
            idx = reshape(idx,1,[]);

            Fs  = obj.Stimuli.SampleRate;
            ids = obj.Stimuli.IDs();
            col = lines(max(numel(idx),2));

            % Spectra are computed before anything is drawn: the overlay needs
            % one common 0 dB reference, which is not known until the loudest
            % entry in the selection has been transformed.
            [f,mag] = deal(cell(1,numel(idx)));
            for k = 1:numel(idx)
                [f{k},mag{k}] = obj.spectrum(double(obj.Stimuli.signal(idx(k))),Fs);
            end
            ref = max(cellfun(@max,mag));
            if ~isfinite(ref) || ref <= 0, ref = 1; end

            obj.clearAxes();
            hold(obj.axWave,'on'); hold(obj.axSpec,'on');
            for k = 1:numel(idx)
                w = double(obj.Stimuli.signal(idx(k)));
                t = 1e3*(0:numel(w)-1)/Fs;
                plot(obj.axWave,t,w,'Color',col(k,:),'LineWidth',1);
                plot(obj.axSpec,f{k}/1e3,20*log10(mag{k}/ref + eps), ...
                    'Color',col(k,:),'LineWidth',1);
            end
            hold(obj.axWave,'off'); hold(obj.axSpec,'off');

            % Longest entry sets the time axis so overlaid traces stay aligned.
            tMax = 1e3*max(obj.Stimuli.duration(idx));
            if tMax > 0, obj.axWave.XLim = [0 tMax]; end
            obj.axSpec.XLim = [0.1 Fs/2e3];
            obj.axSpec.YLim = [-90 5];

            if numel(idx) > 1
                legend(obj.axWave,ids(idx),'Location','northeast','Box','off', ...
                    'AutoUpdate','off','Interpreter','none');
                title(obj.axWave,sprintf('%d of %d stimuli',numel(idx),obj.count()), ...
                    'Interpreter','none');
            else
                title(obj.axWave,ids{idx},'Interpreter','none');
            end

            obj.Info.Value = obj.describe(idx);
        end

        function clearAxes(obj)
            cla(obj.axWave,'reset'); cla(obj.axSpec,'reset');
            xlabel(obj.axWave,'Time (ms)');     ylabel(obj.axWave,'Amplitude');
            xlabel(obj.axSpec,'Frequency (kHz)'); ylabel(obj.axSpec,'Magnitude (dB re peak)');
            grid(obj.axWave,'on'); box(obj.axWave,'on');
            grid(obj.axSpec,'on'); box(obj.axSpec,'on');
            obj.axSpec.XScale = 'log';
        end

        function txt = describe(obj,idx)
            % Details pane: everything about one entry, or a roll-call of many.
            Fs = obj.Stimuli.SampleRate;
            if isscalar(idx)
                m = obj.Stimuli.meta(idx);
                w = double(obj.Stimuli.signal(idx));
                txt = { ...
                    sprintf('ID        %s',m.ID)
                    sprintf('entry     %d of %d',idx,obj.count())
                    sprintf('duration  %.3f ms (%d samples)',1e3*numel(w)/Fs,numel(w))
                    sprintf('rate      %g Hz',Fs)
                    sprintf('peak      %.4g',max(abs(w)))
                    sprintf('rms       %.4g',sqrt(mean(w.^2)))
                    sprintf('alt. pol. %s',yesNo(m.alternatePolarity))};
                % Label(1) is the ID, already shown above; the rest are the
                % passthrough parameters the offline pipeline groups by.
                if numel(m.Label) > 1
                    txt = [txt; {''; 'parameters'}; m.Label(2:end)'];
                end
            else
                txt = {sprintf('%d stimuli selected',numel(idx)); ''};
                ids = obj.Stimuli.IDs();
                d   = obj.Stimuli.duration(idx);
                for k = 1:numel(idx)
                    txt{end+1,1} = sprintf('%d. %s  (%.2f ms)',idx(k),ids{idx(k)},1e3*d(k)); %#ok<AGROW>
                end
            end
        end
    end

    methods (Static, Access = private)
        function [f,mag] = spectrum(w,Fs)
            % Single-sided magnitude spectrum of one presentation. Windowed
            % because a gated pip ends abruptly, and zero-padded to a floor so
            % a very short stimulus still resolves something to look at.
            n    = numel(w);
            nfft = 2^nextpow2(max(n,4096));
            Y    = abs(fft(w(:).*hann(n),nfft));
            keep = 1:floor(nfft/2)+1;
            mag  = Y(keep)';
            f    = (keep-1)*Fs/nfft;
        end
    end
end

% ======================= local helpers ================================
function s = yesNo(tf)
if tf, s = 'yes'; else, s = 'no'; end
end
