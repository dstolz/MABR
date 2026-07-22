function [tf,msg] = stimgenAvailable()
% mabr.stim.stimgenAvailable  Is the stimgen submodule on the path?
%
%   tf = mabr.stim.stimgenAvailable() returns true when the stimgen package
%   (external/stimgen, a git submodule) has been initialized and is visible to
%   MATLAB.
%
%   [tf,msg] = ... also returns an actionable message for the false case,
%   suitable for a status line or a disabled control's tooltip.
%
%   stimgen is an OPTIONAL dependency. It is the suggested way to build a
%   calibrated stimulus bank, but MABR's stimulus contract is the plain struct
%   array (see mabr.stim.StimulusSet) and the .mat and demo routes work with no
%   stimgen at all -- so nothing here belongs in mabr.Config.RequiredToolboxes,
%   and a clone that never ran "git submodule update --init" must still launch.
%   Its MATLAB floor (R2021a) is below MABR's own (R2021b), so presence is the
%   only thing worth checking; there is no version gate.
%
%   See also mabr.stim.fromStimgen, mabr.stim.CalibrationAdapter.
%
% Daniel Stolzberg (c) 2026

tf = exist('stimgen.StimType','class') == 8;

if tf
    msg = '';
else
    msg = ['The stimgen package is not on the MATLAB path. It ships as a git ' ...
           'submodule: run "git submodule update --init" in the MABR folder, ' ...
           'then restart MABR.'];
end
end
