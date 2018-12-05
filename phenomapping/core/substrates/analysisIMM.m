function [model, drains, modelpre] = analysisIMM(model, flagUpt, minObj, ...
    maxObj, drainsForiMM, rxnNoThermo, ReactionDB, metabData)
% Identifies In silico Minimal Media (IMM) or In silico Minimal Secretion
% (IMS) to achieve a given objective
%
% USAGE:
%
%    [model, drains] = analysisIMM(model, flagUpt, minObj, maxObj, drainsForiMM, rxnNoThermo, ReactionDB, metabData)
%
% INPUT:
%    model:           TFA model structure
%
% OPTIONAL INPUTS:
%    flagUpt:         True to identify the In silico Minimal Media (IMM). 
%                     Else it gets the In silico Minimal Secretion (IMS).
%                     (default = true)
%    minObj:          Objective lower bound (default = 90% optimal value)
%    maxObj:          Objective upper bound (default = optimal value)
%    drainsForiMM:    Drains or transports to minimize (default = all drains)
%    rxnNoThermo:     List of rxns for which no thermo constraints should 
%                     be applied (default = all rxns -- equivalent to FBA)
%    ReactionDB:      Database with all the thermodynamic information from
%                     Alberty (default = DB_AlbertyUpdate.mat in matTFA)
%    metabData:       Metabolomics data (default = empty)
% 
%
% OUTPUTS:
%    model:           Model with MILP formulation for IMM analysis
%    drains:          Drains used for the analysis
%    modelpre:        Model ready for MILP formulation
%
% .. Author:
% Meric Ataman 2014
% Anush Chiappino-Pepe 2017 : minimal secretion and refinement
% 

solWT=optimizeThermoModel(model);

if (nargin < 2)
    flagUpt = 1;
end
if (nargin < 3)
    minObj = 0.9*solWT.val;
end
if (nargin < 4)
    maxObj = solWT.val;
end
if (nargin < 5)
    drainsForiMM = {};
end
if (nargin < 6)
    % default = FBA analysis
    rxnNoThermo = model.rxns;
end
if (nargin < 7)
    ReactionDB = load('/phenomapping/ext/matTFA/thermoDatabases/thermo_data.mat');
    ReactionDB = ReactionDB.DB_AlbertyUpdate;
end
if (nargin < 8)
    metabData = [];
end

if (minObj > maxObj)
    error('the defined lower bound (minObj) is bigger than the upper bound (maxObj) of the objective')
end

fprintf('getting model drains\n');
[model, flagChange, drains, drainMets] = putDrainsForward(model);
if ~isempty(drainsForiMM)
    if ((sum(ismember(drainsForiMM,model.rxns)) == length(drainsForiMM)) || (sum(ismember(drainsForiMM,drains)) == length(drainsForiMM)))
        drains = drainsForiMM;
        drainMets = printRxnFormula(model,drains,0,0,1);
    else
        fprintf('CAUTION: Not all drainsForiMM were identified as drains or rxns\n');
        fprintf('The analysis will be done for all substrates\n');
    end
end

if flagUpt
    drains = [strcat('R_', drains) drainMets]; % get uptakes
else
    drains = [strcat('F_', drains) drainMets]; % get secretions
end
if flagChange
    fprintf('some drains had to be redefined -> reconvert to thermo: for this it is recommended to download the matTFA repository and not depend on the limited functions provided in the folder ext of this repository\n');
    model = prepModelforTFA(model, ReactionDB, model.CompartmentData);
end
if (flagChange || (length(rxnNoThermo) == length(model.rxns)))
    fprintf('generating TFA structure: for this it is recommended to download the matTFA repository and not depend on the limited functions provided in the folder ext of this repository\n');
    model = convToTFA(model, ReactionDB, rxnNoThermo);
end
model.indNF = getAllVar(model,{'NF'});
if isempty(model.indNF)
    model = addNetFluxVariables(model);
    model.indNF = getAllVar(model,{'NF'});
end
if ~isempty(metabData)
    model = loadConstraints(model,metabData);
end
modelpre = model;

model.var_lb(model.f==1) = minObj;
model.var_ub(model.f==1) = maxObj;
model.f = zeros(length(model.varNames),1);
model.objtype = -1; %maximize

[~, rowDrain] = ismember(drains(:,1), model.varNames);

fprintf('defining MILP problem\n');
intTag = {'BFUSE'}; % integer tag used in this MILP
[~,num_vars] = size(model.A);
indUSE = zeros(size(drains,1),1);
for i=1:size(drains,1)
    model.varNames(num_vars+i) = strcat(intTag, '_', drains(i,1));
    model.var_ub(num_vars+i) = 1;
    model.var_lb(num_vars+i) = 0;
    model.vartypes(num_vars+i) = {'B'};
    model.f(num_vars+i) = 1;
    indUSE(i) = num_vars+i;
end
model.indUSE = indUSE;

% define constraints for MILP
% if flagUpt == 1 : maximize blocked uptakes (R_rxns)
% 100 * BFUSE_R_rxn + R_rxn < 50
% BFUSE_R_rxn = 1 -> R_rxn = 0
% BFUSE_R_rxn = 0 -> R_rxn < 50

% if flagUpt == 0 : maximize blocked secretions (F_rxns)
% 100 * BFUSE_F_rxn + F_rxn < 50
% BFUSE_F_rxn = 1 -> F_rxn = 0
% BFUSE_F_rxn = 0 -> F_rxn < 50
[num_constr,~] = size(model.A);
for i=1:length(rowDrain)
    model.rhs(num_constr+i,1) =  50;
    model.constraintNames{num_constr+i,1} = strcat('BFMER_',num2str(i));
    model.constraintType{num_constr+i,1} = '<';
    model.A(num_constr+i,rowDrain(i)) = 1;
    model.A(num_constr+i,num_vars+i) = 50;
end
end