classdef Schedule < handle
    
    properties
        
    end
    
    properties (GetAccess = public, SetAccess = private)
        SIG
        compiled
    end
    
    properties (Access = private)
        data
        
        scheduleLabel;
        scheduleTable;
        scheduleFig;
    end
    
    methods
        
        function obj = Schedule
            
        end
        
        
        function delete(obj)
            
        end
        
        
        
        function preprocess(obj,type,props,data,sigFiles)
            
            obj.SIG = sigdef.sigs.(type);
            
            for i = 1:length(props)
                if isprop(obj.SIG,['M_' props{i}])
                    % modification
                    switch eval(['obj.SIG.M_' props{i}])
                        case 'string'
                            S.(props{i}).values = data{i,3};
                            S.(props{i}).N = 1;
                            S.(props{i}).type = 'string';
                            
                        case 'files'
                            S.(props{i}).values = sigFiles;
                            S.(props{i}).N = numel(sigFiles);
                            S.(props{i}).filenames = cellfun(@(a) a(find(a==filesep,1,'last')+1:end),sigFiles,'uni',0);
                            S.(props{i}).type = 'files';
                            
                        otherwise
                            fprintf(2,'Unknown property modification: %s',eval(['M_' props{i}]))
                    end
                else
                    S.(props{i}).values = eval(data{i,3});
                    S.(props{i}).N = numel(S.(props{i}).values);
                    S.(props{i}).type = 'numeric';
                end
            end
            
            
            obj.data = S;
        end
        
        function compile(obj)
            
            S = obj.data;
            props = fieldnames(S);
            
            C = [];
            
            N = structfun(@(a) a.N,S);
            
            
            for j = 1:length(props)
                if ~isequal(S.(props{j}).type,'numeric'), continue; end
                vj = S.(props{j}).values;
                if isempty(C)
                    C(:,j) = vj(:);
                else
                    if N(j) > 1
                        C = [C; repmat(C,N(j)-1,1)];
                        vje = repmat(vj,size(C,1)/N(j),1);
                    else
                        vje = repmat(vj,size(C,1),1);
                    end
                    C(:,j) = vje(:);
                end
            end
            
            obj.compiled = C;
        end
        
        function update(obj)
            
            sh = findobj('type','figure','-and','Name','Schedule');
            
            if isempty(sh)
                obj.scheduleFig = figure('name','Schedule', 'Position',[600 200 600 500], ...
                    'MenuBar','none','IntegerHandle','off');
                
                % Schedule Design Table
                obj.scheduleLabel = uicontrol(obj.scheduleFig,'Style','text');
                obj.scheduleLabel.Position = [110 470 380 30];
                obj.scheduleLabel.String = 'Schedule';
                obj.scheduleLabel.FontSize = 16;
                
                obj.scheduleTable = uitable(obj.scheduleFig,'Tag','Schedule');
                obj.scheduleTable.Position = [20 20 560 440];
                obj.scheduleTable.FontSize = 10;
                obj.scheduleTable.ColumnEditable = false;
            end
            
            fn = fieldnames(obj.data);
            
            
            obj.scheduleTable.Data = obj.compiled;
            obj.scheduleTable.ColumnName = fn;
        end
    end
    
end