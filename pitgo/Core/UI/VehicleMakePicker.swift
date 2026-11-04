import SwiftUI

struct VehicleMakePicker: View {
    @Binding var selection: String
    private let makes = ["Agrale", "Audi", "BMW", "CAOA Chery", "Chevrolet", "Citroën", "DAF", "Dodge", "Fiat", "Ford", "Foton", "Honda", "Hyundai", "Iveco", "JAC", "Jeep", "Kia", "Land Rover", "MAN", "Mercedes-Benz", "Mitsubishi", "Nissan", "Peugeot", "Porsche", "RAM", "Renault", "Scania", "Subaru", "Suzuki", "Toyota", "Volkswagen", "Volvo"]
    var body: some View {
        Picker("Marca", selection: $selection) {
            Text("Selecionar marca").tag("")
            if !selection.isEmpty, !makes.contains(selection) { Text(selection).tag(selection) }
            ForEach(makes, id: \.self) { Text($0).tag($0) }
        }
    }
}
