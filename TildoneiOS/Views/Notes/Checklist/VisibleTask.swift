import TildoneDomain

struct VisibleTask: Identifiable {
    let index: Int
    let task: TildoneDomain.Task

    var id: TaskID { task.id }
}
