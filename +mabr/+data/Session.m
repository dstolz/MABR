classdef Session < handle
% mabr.data.Session  Top-level acquisition session.
%
%   A handle object holding the session-wide configuration (subject, device,
%   sample rates), the presentation schedule that drives acquisition, and the
%   array of completed mabr.data.Block results. Replaces the session-level
%   role that abr.ABR played, minus the tangled Buffer/back-reference model.
%
% Daniel Stolzberg (c) 2019-2026

    properties
        Subject       (1,1) struct = struct('ID','');   % subject metadata (ID, ...)
        Device        (1,:) char   = '';                % ASIO device name
        DACSampleRate (1,1) double = 192000;
        ADCSampleRate (1,1) double = 12000;

        OutputPath    (1,:) char = '';                  % folder for .abr files
        Schedule                                        % mabr.stim.Schedule

        Blocks        (1,:) mabr.data.Block             % completed results
        StartTime     (1,:) char = '';

        % The rig notebook for this session (mabr.data.SessionNotes), a HANDLE
        % shared with whoever is displaying it -- mabr.ui.App hands its own
        % store in here at Start so the notes the operator has already taken
        % follow the session rather than starting over. Deliberately NOT given
        % a property default: a handle default is evaluated once at class load
        % and would then be the SAME store in every Session ever constructed.
        % Every file the session writes carries the whole log as of the moment
        % it was written; see mabr.data.SessionNotes.
        Notes         mabr.data.SessionNotes
    end

    properties (Dependent)
        DecimationFactor
        NumBlocks
    end

    methods
        function obj = Session(cfg)
            if nargin >= 1 && ~isempty(cfg)
                obj.DACSampleRate = cfg.DACSampleRate;
                obj.ADCSampleRate = cfg.ADCSampleRate;
            end
            obj.StartTime = char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss'));
            obj.Notes     = mabr.data.SessionNotes();
        end

        function f = get.DecimationFactor(obj)
            f = obj.DACSampleRate ./ obj.ADCSampleRate;
        end

        function n = get.NumBlocks(obj)
            n = numel(obj.Blocks);
        end

        function addBlock(obj,block)
            if isempty(obj.Blocks)
                obj.Blocks = block;
            else
                obj.Blocks(end+1) = block;
            end
        end

        function S = noteRecord(obj)
            % The session's notebook as a plain struct array, ready to write
            % into a data file. Empty -- but with the right fields -- when
            % there is no store, so a Session built by hand in a test still
            % produces a file offline code can read unconditionally.
            if isempty(obj.Notes) || ~isvalid(obj.Notes)
                S = mabr.data.SessionNotes.emptyRecord();
            else
                S = obj.Notes.toStruct();
            end
        end

        function ffn = saveBlock(obj,block,baseName)
            % Write one completed block to an offline-compatible .abr file.
            if nargin < 3 || isempty(baseName)
                baseName = obj.Subject.ID;
            end
            ffn = mabr.data.io.writeABR(block,obj.OutputPath,baseName);
        end
    end
end
