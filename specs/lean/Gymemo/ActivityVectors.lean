import Gymemo.Activities

namespace Gymemo.Activities

def sampleCommands : List Command := [.record ⟨5, 1, 20776, 20, (some 1500)⟩, .record ⟨5, 1, 20776, 20, (some 1500)⟩, .record ⟨6, 2, 20776, 10, none⟩, .add ⟨2, 1, false⟩, .add ⟨3, 1, true⟩, .add ⟨3, 2, true⟩, .record ⟨6, 2, 20776, 10, (some 1500)⟩, .record ⟨6, 2, 20776, 10, none⟩, .edit 6 10 (some 1500), .edit 5 20 (some 1500), .edit 5 10 none, .delete 6, .delete 6]

def sampleSteps : List (Option (List Change)) := [some [.putRecord ⟨5, 1, 20776, 20, (some 1500)⟩], none, none, some [.putActivity ⟨2, 1, false⟩], none, some [.putActivity ⟨3, 2, true⟩], none, some [.putRecord ⟨6, 2, 20776, 10, none⟩], none, some [], some [.putRecord ⟨5, 1, 20776, 10, none⟩], some [.removeRecord 6], none]

def finalLog : Log := ⟨[⟨2, 1, false⟩, ⟨3, 2, true⟩], [⟨5, 1, 20776, 10, none⟩]⟩

example : run empty sampleCommands = (sampleSteps, finalLog) := by decide

end Gymemo.Activities
