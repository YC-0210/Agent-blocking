"""Copy the production view into the simulator-only capture harness.

Only the initial setup step is injectable in this copy. No fixture code is added to
production and all rendering/validation/actions remain the actual view source.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
source = (root / 'DoCard/AgentFocus/AgentFocusView.swift').read_text()
source = source.replace(
    'step = .connection',
    'step = SetupStep(rawValue: ProcessInfo.processInfo.arguments.contains("setup-limits") ? 2 : 0)!',
)
(root / 'tools/ui-capture/App/AgentFocusView.swift').write_text(source)
