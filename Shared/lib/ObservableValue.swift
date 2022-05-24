//
//  ObservableValue.swift
//  warpinator-project
//
//  Created by Emanuel on 24/05/2022.
//


class ObservableValue<ValueType>: ObservableObject {
    @Published
    fileprivate var state: ValueType

    init(_ initial: ValueType) {
        self.state = initial
    }

    var wrappedValue: ValueType {
        get { return state }
    }
}

class MutableObservableValue<ValueType>: ObservableValue<ValueType> {
    override var wrappedValue: ValueType {
        get { return state }
        set { state = newValue }
    }
}
